//
//  ImportConversationsUseCase.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 13/07/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

protocol ImportConversationsUseCaseProtocol: Sendable {
    func execute(_ data: Data) async throws -> ImportConversationsResult
}

struct ImportConversationsUseCase: ImportConversationsUseCaseProtocol {
    // MARK: - Properties

    private let saveConversationUseCase: SaveConversationUseCaseProtocol
    private let loadConversationsUseCase: LoadConversationsUseCaseProtocol

    // MARK: - Init

    init(
        saveConversationUseCase: SaveConversationUseCaseProtocol = SaveConversationUseCase(),
        loadConversationsUseCase: LoadConversationsUseCaseProtocol = LoadConversationsUseCase()
    ) {
        self.saveConversationUseCase = saveConversationUseCase
        self.loadConversationsUseCase = loadConversationsUseCase
    }

    // MARK: - Execute

    func execute(_ data: Data) async throws -> ImportConversationsResult {
        let document = try decodeDocument(from: data)
        try validate(document)
        let context = ImportContext(
            conversationIds: makeConversationIds(for: document),
            messageIds: makeMessageIds(for: document),
            attachmentData: makeAttachmentData(for: document),
            tagColors: try await makeTagColors(for: document)
        )
        return try await importDocument(document, context: context)
    }
}

// MARK: - Private

private extension ImportConversationsUseCase {
    typealias AttachmentData = [UUID: [UUID: String]]

    struct ImportContext {
        let conversationIds: [UUID: UUID]
        let messageIds: [UUID: UUID]
        let attachmentData: AttachmentData
        let tagColors: [String: TagColor]
    }

    struct RestoredConversation {
        let conversation: Conversation
        let attachments: [ChatMessage.Attachment]
        let skippedAttachmentCount: Int
    }

    struct AttachmentRestoration {
        var saved: [ChatMessage.Attachment] = []
        var skippedCount = 0
    }

    func decodeDocument(from data: Data) throws -> ConversationExportDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let document = try decoder.decode(ConversationExportDocument.self, from: data)
            guard document.format == ConversationExportDocument.formatIdentifier else {
                throw ImportConversationsError.unsupportedFormat
            }
            guard document.version == ConversationExportDocument.currentVersion else {
                throw ImportConversationsError.unsupportedVersion
            }
            return document
        } catch let error as ImportConversationsError {
            throw error
        } catch {
            throw ImportConversationsError.invalidDocument
        }
    }

    func validate(_ document: ConversationExportDocument) throws {
        let conversationIds = document.conversations.map(\.conversation.id)
        guard Set(conversationIds).count == conversationIds.count else {
            throw ImportConversationsError.duplicateConversationIdentifier
        }
        let messageIds = document.conversations.flatMap { $0.conversation.messages.map(\.id) }
        guard Set(messageIds).count == messageIds.count else {
            throw ImportConversationsError.duplicateMessageIdentifier
        }
        do {
            try document.conversations.forEach { try $0.conversation.validateContextMetadata() }
        } catch {
            throw ImportConversationsError.invalidDocument
        }
        try validateAttachmentReferences(in: document)
    }

    func validateAttachmentReferences(in document: ConversationExportDocument) throws {
        var attachmentIds = [UUID: Set<UUID>]()
        for exportedConversation in document.conversations {
            for message in exportedConversation.conversation.messages {
                attachmentIds[message.id] = Set(message.attachments.map(\.id))
            }
        }
        var payloadIds = [UUID: Set<UUID>]()
        for exportedConversation in document.conversations {
            for attachment in exportedConversation.attachments {
                guard attachmentIds[attachment.messageId]?.contains(attachment.attachmentId) == true else {
                    throw ImportConversationsError.invalidAttachmentReference
                }
                guard payloadIds[attachment.messageId, default: []].insert(attachment.attachmentId).inserted else {
                    throw ImportConversationsError.duplicateAttachmentPayload
                }
            }
        }
    }

    func makeConversationIds(for document: ConversationExportDocument) -> [UUID: UUID] {
        Dictionary(uniqueKeysWithValues: document.conversations.map { exportedConversation in
            (exportedConversation.conversation.id, UUID())
        })
    }

    func makeMessageIds(for document: ConversationExportDocument) -> [UUID: UUID] {
        Dictionary(uniqueKeysWithValues: document.conversations.flatMap { exportedConversation in
            exportedConversation.conversation.messages.map { ($0.id, UUID()) }
        })
    }

    func makeAttachmentData(for document: ConversationExportDocument) -> AttachmentData {
        document.conversations.reduce(into: [:]) { data, exportedConversation in
            for attachment in exportedConversation.attachments {
                data[attachment.messageId, default: [:]][attachment.attachmentId] = attachment.data
            }
        }
    }

    func makeTagColors(for document: ConversationExportDocument) async throws -> [String: TagColor] {
        let importedTags = document.conversations.flatMap(\.conversation.tags)
        return (try await loadConversationsUseCase.execute().flatMap(\.tags) + importedTags)
            .reduce(into: [String: TagColor]()) { colors, tag in
                if colors[tag.name] == nil {
                    colors[tag.name] = tag.color
                }
            }
    }

    func importDocument(
        _ document: ConversationExportDocument,
        context: ImportContext
    ) async throws -> ImportConversationsResult {
        var result = ImportConversationsResult(
            importedConversationCount: 0,
            restoredAttachmentCount: 0,
            skippedAttachmentCount: 0
        )
        var restoredConversations: [Conversation] = []
        for exportedConversation in document.conversations {
            let restored = try restoreConversation(exportedConversation.conversation, context: context)
            restoredConversations.append(restored.conversation)
            result = ImportConversationsResult(
                importedConversationCount: result.importedConversationCount + 1,
                restoredAttachmentCount: result.restoredAttachmentCount + restored.attachments.count,
                skippedAttachmentCount: result.skippedAttachmentCount + restored.skippedAttachmentCount
            )
        }
        _ = try await saveConversationUseCase.executeImportBatch(restoredConversations)
        return result
    }

    func restoreConversation(
        _ conversation: Conversation,
        context: ImportContext
    ) throws -> RestoredConversation {
        guard let conversationId = context.conversationIds[conversation.id] else {
            throw ImportConversationsError.invalidDocument
        }
        var attachmentRestoration = AttachmentRestoration()
        let imageReferences = ImageReferences(conversation: conversation, attachmentData: context.attachmentData)
        let messages = try conversation.messages.map { message in
            try restoreMessage(
                message,
                context: context,
                imageReferences: imageReferences,
                attachmentRestoration: &attachmentRestoration
            )
        }
        return RestoredConversation(
            conversation: Conversation(
                id: conversationId,
                title: conversation.title,
                modelId: conversation.modelId,
                systemPrompt: conversation.systemPrompt,
                contextWindowTokens: conversation.contextWindowTokens,
                contextSummary: conversation.contextSummary.map { imageReferences.remapText($0) },
                contextSummaryCursorMessageId: remappedSummaryCursor(for: conversation, context: context),
                messages: messages,
                modelParameters: conversation.modelParameters,
                isPinned: conversation.isPinned,
                tags: conversation.tags.map {
                    ConversationTag(name: $0.name, color: context.tagColors[$0.name] ?? $0.color)
                },
                parentConversationId: conversation.parentConversationId.flatMap { context.conversationIds[$0] },
                branchedFromMessageId: conversation.branchedFromMessageId.flatMap { context.messageIds[$0] },
                createdAt: conversation.createdAt,
                updatedAt: Date()
            ),
            attachments: attachmentRestoration.saved,
            skippedAttachmentCount: attachmentRestoration.skippedCount
        )
    }

    func remappedSummaryCursor(for conversation: Conversation, context: ImportContext) -> UUID? {
        guard let cursor = conversation.contextSummaryCursorMessageId,
              conversation.messages.contains(where: { $0.id == cursor }) else { return nil }
        return context.messageIds[cursor]
    }

    func restoreMessage(
        _ message: ChatMessage,
        context: ImportContext,
        imageReferences: ImageReferences,
        attachmentRestoration: inout AttachmentRestoration
    ) throws -> ChatMessage {
        guard let messageId = context.messageIds[message.id] else {
            throw ImportConversationsError.invalidDocument
        }
        let attachments = restoreAttachments(
            message.attachments,
            messageId: message.id,
            context: context,
            imageReferences: imageReferences,
            attachmentRestoration: &attachmentRestoration
        )
        return ChatMessage(
            id: messageId,
            role: message.role,
            content: imageReferences.remapContent(of: message),
            reasoningContent: message.reasoningContent,
            timestamp: message.timestamp,
            attachments: attachments,
            tokenUsage: message.tokenUsage,
            webSearchResults: message.webSearchResults,
            toolCalls: message.role == .assistant
                ? message.toolCalls?.map { imageReferences.remapToolCall($0) } : message.toolCalls,
            toolCallId: message.toolCallId,
            toolName: message.toolName,
            isFavourite: message.isFavourite,
            imageGenerationAttempted: message.imageGenerationAttempted
        )
    }

    func restoreAttachments(
        _ attachments: [ChatMessage.Attachment],
        messageId: UUID,
        context: ImportContext,
        imageReferences: ImageReferences,
        attachmentRestoration: inout AttachmentRestoration
    ) -> [ChatMessage.Attachment] {
        attachments.compactMap { attachment in
            guard let encodedData = context.attachmentData[messageId]?[attachment.id],
                  let data = Data(base64Encoded: encodedData),
                  let attachmentId = imageReferences.attachmentId(for: attachment.id, messageId: messageId) else {
                attachmentRestoration.skippedCount += 1
                return nil
            }
            let importedAttachment = ChatMessage.Attachment(
                id: attachmentId,
                type: attachment.type,
                fileName: attachment.fileName,
                mimeType: attachment.mimeType,
                fileRelativePath: "",
                transientData: data
            )
            attachmentRestoration.saved.append(importedAttachment)
            return importedAttachment
        }
    }
}

private enum ImportConversationsError: LocalizedError {
    case invalidDocument
    case unsupportedFormat
    case unsupportedVersion
    case duplicateConversationIdentifier
    case duplicateMessageIdentifier
    case invalidAttachmentReference
    case duplicateAttachmentPayload

    var errorDescription: String? {
        switch self {
        case .invalidDocument:
            String(localized: "The backup file is invalid.")
        case .unsupportedFormat:
            String(localized: "This file is not an OpenClient backup.")
        case .unsupportedVersion:
            String(localized: "This backup version is not supported.")
        case .duplicateConversationIdentifier, .duplicateMessageIdentifier, .duplicateAttachmentPayload:
            String(localized: "The backup contains duplicate identifiers.")
        case .invalidAttachmentReference:
            String(localized: "The backup contains an invalid attachment reference.")
        }
    }
}
