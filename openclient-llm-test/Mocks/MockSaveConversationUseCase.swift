//
//  MockSaveConversationUseCase.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 31/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation
@testable import openclient_llm

// Safety: Only used within serialized @MainActor test methods.
final class MockSaveConversationUseCase: SaveConversationUseCaseProtocol, @unchecked Sendable {
    // MARK: - Properties

    var savedConversations: [Conversation] = []
    var expectedBases: [Conversation?] = []
    var creationPlacements: [ConversationCreationPlacement?] = []
    var error: Error?
    var failureAtCall: Int?
    var result: Conversation?
    var executeHandler: ((Conversation, Conversation?) throws -> Conversation)?
    var asyncExecuteHandler: ((Conversation, Conversation?, Int) async throws -> Conversation)?
    var executeCallCount = 0
    var importBatches: [[Conversation]] = []
    var importedOrganizations: [ConversationFolderSnapshot] = []

    // MARK: - Execute

    @discardableResult
    func execute(
        _ conversation: Conversation,
        expectedBase: Conversation?,
        creationPlacement: ConversationCreationPlacement?
    ) async throws -> Conversation {
        executeCallCount += 1
        creationPlacements.append(creationPlacement)
        if let error { throw error }
        if failureAtCall == executeCallCount {
            throw NSError(domain: "MockSaveConversationUseCase", code: 1)
        }
        savedConversations.append(conversation)
        expectedBases.append(expectedBase)
        if let asyncExecuteHandler {
            return try await asyncExecuteHandler(conversation, expectedBase, executeCallCount)
        }
        if let executeHandler {
            return try executeHandler(conversation, expectedBase)
        }
        return result ?? conversation
    }

    func executeImportBatch(
        _ conversations: [Conversation],
        organization: ConversationFolderSnapshot
    ) async throws -> [Conversation] {
        if let error { throw error }
        importBatches.append(conversations)
        importedOrganizations.append(organization)
        savedConversations.append(contentsOf: conversations)
        return conversations
    }
}
