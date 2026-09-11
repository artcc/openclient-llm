//
//  BranchConversationUseCase.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 03/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

enum BranchConversationError: LocalizedError {
    case messageNotFound

    var errorDescription: String? {
        switch self {
        case .messageNotFound:
            String(localized: "The message to fork from could not be found.")
        }
    }
}

protocol BranchConversationUseCaseProtocol: Sendable {
    func execute(conversation: Conversation, fromMessageId: UUID) async throws -> Conversation
}

struct BranchConversationUseCase: BranchConversationUseCaseProtocol {
    // MARK: - Properties

    private let saveConversationUseCase: SaveConversationUseCaseProtocol
    private let attachmentRepository: AttachmentRepositoryProtocol

    // MARK: - Init

    init(
        saveConversationUseCase: SaveConversationUseCaseProtocol = SaveConversationUseCase(),
        attachmentRepository: AttachmentRepositoryProtocol = AttachmentRepository()
    ) {
        self.saveConversationUseCase = saveConversationUseCase
        self.attachmentRepository = attachmentRepository
    }

    // MARK: - Execute

    func execute(conversation: Conversation, fromMessageId: UUID) async throws -> Conversation {
        guard let messageIndex = conversation.messages.firstIndex(where: { $0.id == fromMessageId }) else {
            throw BranchConversationError.messageNotFound
        }

        let forkId = UUID()
        let sourceMessages = Array(conversation.messages.prefix(messageIndex + 1))
        let retainsSummary = conversation.contextSummaryCursorMessageId.flatMap { cursorMessageId in
            conversation.messages.firstIndex(where: { $0.id == cursorMessageId })
        }.map { $0 <= messageIndex } ?? false
        let branchedMessages = try cloneMessages(sourceMessages)
        let messageIds = Dictionary(uniqueKeysWithValues: zip(sourceMessages, branchedMessages).map { pair in
            (pair.0.id, pair.1.id)
        })
        let fork = Conversation(
            id: forkId,
            modelId: conversation.modelId,
            systemPrompt: conversation.systemPrompt,
            contextWindowTokens: conversation.contextWindowTokens,
            contextSummary: retainsSummary ? conversation.contextSummary : nil,
            contextSummaryCursorMessageId: retainsSummary
                ? conversation.contextSummaryCursorMessageId.flatMap { messageIds[$0] }
                : nil,
            messages: branchedMessages,
            modelParameters: conversation.modelParameters,
            isPinned: false,
            tags: conversation.tags,
            parentConversationId: conversation.id,
            branchedFromMessageId: fromMessageId
        )

        return try await saveConversationUseCase.execute(fork)
    }
}

// MARK: - Private

private extension BranchConversationUseCase {
    func cloneMessages(_ messages: [ChatMessage]) throws -> [ChatMessage] {
        try messages.map { message in
            var attachments = message.attachments
            for attachmentIndex in attachments.indices {
                let source = attachments[attachmentIndex]
                let data: Data
                if let transientData = source.transientData {
                    data = transientData
                } else {
                    data = try attachmentRepository.load(attachment: source)
                }
                attachments[attachmentIndex] = ChatMessage.Attachment(
                    id: source.id,
                    type: source.type,
                    fileName: source.fileName,
                    mimeType: source.mimeType,
                    fileRelativePath: "",
                    transientData: data
                )
            }
            return ChatMessage(
                role: message.role,
                content: message.content,
                reasoningContent: message.reasoningContent,
                timestamp: message.timestamp,
                attachments: attachments,
                tokenUsage: message.tokenUsage,
                webSearchResults: message.webSearchResults,
                toolCalls: message.toolCalls,
                toolCallId: message.toolCallId,
                toolName: message.toolName,
                isFavourite: message.isFavourite,
                imageGenerationAttempted: message.imageGenerationAttempted
            )
        }
    }
}
