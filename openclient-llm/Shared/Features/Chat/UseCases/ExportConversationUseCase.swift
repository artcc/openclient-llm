//
//  ExportConversationUseCase.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 03/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

protocol ExportConversationUseCaseProtocol: Sendable {
    func execute(_ conversation: Conversation) throws -> Data
}

/// Exports a conversation in the versioned, self-contained backup format.
///
/// Attachment files stored on disk are loaded and stored as base64 strings so the
/// exported document remains portable across devices.
struct ExportConversationUseCase: ExportConversationUseCaseProtocol {
    // MARK: - Properties

    private let exportConversationsUseCase: ExportConversationsUseCaseProtocol

    // MARK: - Init

    init(attachmentRepository: AttachmentRepositoryProtocol = AttachmentRepository()) {
        exportConversationsUseCase = ExportConversationsUseCase(attachmentRepository: attachmentRepository)
    }

    // MARK: - Execute

    func execute(_ conversation: Conversation) throws -> Data {
        try exportConversationsUseCase.execute([conversation], organization: nil)
    }
}
