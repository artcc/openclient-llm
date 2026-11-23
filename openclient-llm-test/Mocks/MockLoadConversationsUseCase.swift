//
//  MockLoadConversationsUseCase.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 31/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation
@testable import openclient_llm

// Safety: Only used within serialized @MainActor test methods.
final class MockLoadConversationsUseCase: LoadConversationsUseCaseProtocol, @unchecked Sendable {
    // MARK: - Properties

    var result: Result<[Conversation], Error> = .success([])
    var executeCallCount = 0
    var executeLocallyCallCount = 0

    // MARK: - Execute

    func execute() async throws -> [Conversation] {
        executeCallCount += 1
        return try result.get()
    }

    func executeLocally() async throws -> [Conversation] {
        executeLocallyCallCount += 1
        return try result.get()
    }

    func executeForBackup() async throws -> ConversationBackupSnapshot {
        (try result.get(), ConversationFolderSnapshot(folders: [], memberships: []))
    }
}
