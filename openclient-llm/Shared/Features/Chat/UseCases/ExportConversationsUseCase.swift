//
//  ExportConversationsUseCase.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 13/07/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

protocol ExportConversationsUseCaseProtocol: Sendable {
    func execute(_ conversations: [Conversation], organization: ConversationFolderSnapshot?) throws -> Data
}

struct ExportConversationsUseCase: ExportConversationsUseCaseProtocol {
    // MARK: - Properties

    private let attachmentRepository: AttachmentRepositoryProtocol

    // MARK: - Init

    init(attachmentRepository: AttachmentRepositoryProtocol = AttachmentRepository()) {
        self.attachmentRepository = attachmentRepository
    }

    // MARK: - Execute

    func execute(_ conversations: [Conversation], organization: ConversationFolderSnapshot? = nil) throws -> Data {
        try conversations.forEach { try $0.validateContextMetadata() }
        let document = ConversationExportDocument(
            conversations: conversations.map(exportedConversation),
            organization: organization
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    // MARK: - Private

    private func exportedConversation(
        _ conversation: Conversation
    ) -> ConversationExportDocument.ExportedConversation {
        .init(conversation: conversation, attachments: exportedAttachments(for: conversation))
    }

    private func exportedAttachments(
        for conversation: Conversation
    ) -> [ConversationExportDocument.ExportedAttachment] {
        conversation.messages.flatMap { message in
            message.attachments.compactMap { attachment in
                let data: Data?
                if let transientData = attachment.transientData {
                    data = transientData
                } else if !attachment.fileRelativePath.isEmpty {
                    data = try? attachmentRepository.load(attachment: attachment)
                } else {
                    data = nil
                }
                guard let data else { return nil }
                return .init(
                    messageId: message.id,
                    attachmentId: attachment.id,
                    data: data.base64EncodedString()
                )
            }
        }
    }
}
