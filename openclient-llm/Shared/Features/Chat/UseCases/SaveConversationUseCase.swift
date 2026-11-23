//
//  SaveConversationUseCase.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 31/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

protocol SaveConversationUseCaseProtocol: Sendable {
    @discardableResult
    func execute(
        _ conversation: Conversation,
        expectedBase: Conversation?,
        creationPlacement: ConversationCreationPlacement?
    ) async throws -> Conversation
    func executeImportBatch(
        _ conversations: [Conversation],
        organization: ConversationFolderSnapshot
    ) async throws -> [Conversation]
}

extension SaveConversationUseCaseProtocol {
    @discardableResult
    func execute(_ conversation: Conversation, expectedBase: Conversation? = nil) async throws -> Conversation {
        try await execute(conversation, expectedBase: expectedBase, creationPlacement: nil)
    }
}

struct SaveConversationUseCase: SaveConversationUseCaseProtocol {
    // MARK: - Properties

    private let repository: ConversationRepositoryProtocol

    // MARK: - Init

    init(repository: ConversationRepositoryProtocol = ConversationRepository()) {
        self.repository = repository
    }

    // MARK: - Execute

    @discardableResult
    func execute(
        _ conversation: Conversation,
        expectedBase: Conversation?,
        creationPlacement: ConversationCreationPlacement?
    ) async throws -> Conversation {
        let saved = try await repository.save(
            conversation,
            expectedBase: expectedBase,
            creationPlacement: creationPlacement
        )
        SpotlightManager.index(saved)
        return saved
    }

    func executeImportBatch(
        _ conversations: [Conversation],
        organization: ConversationFolderSnapshot
    ) async throws -> [Conversation] {
        let saved = try await repository.importBatch(conversations, organization: organization)
        saved.forEach(SpotlightManager.index)
        return saved
    }
}
