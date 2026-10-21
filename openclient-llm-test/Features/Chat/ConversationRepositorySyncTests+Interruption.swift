//
//  ConversationRepositorySyncTests+Interruption.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 21/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

extension ConversationRepositorySyncTests {
    func test_save_interruptionOnlyChange_persistsAndSynchronizesWithoutLosingRemoteMetadata() async throws {
        // Given
        let message = ChatMessage(role: .assistant, content: "Partial")
        let conversation = Conversation(modelId: "test", messages: [ChatMessage(role: .user, content: "Ask"), message])
        settingsManager.isCloudSyncEnabled = false
        let base = try await sut.save(conversation)
        var remote = base
        remote.title = "Remote title"
        remote.updatedAt = base.updatedAt.addingTimeInterval(1)
        cloudSyncManager.cloudConversations = [remote]
        settingsManager.isCloudSyncEnabled = true
        var interrupted = base
        interrupted.messages[1].responseInterruption = .backgroundTaskEnded

        // When
        let saved = try await sut.save(interrupted, expectedBase: base)
        let reloaded = try await sut.loadLocal()

        // Then
        XCTAssertEqual(saved.title, "Remote title")
        XCTAssertEqual(saved.messages.last?.responseInterruption, .backgroundTaskEnded)
        XCTAssertEqual(reloaded.first?.messages, saved.messages)
        XCTAssertEqual(cloudSyncManager.cloudConversations.first?.messages, saved.messages)
    }

    func test_save_interruptedSnapshotAfterDeletion_doesNotResurrectConversation() async throws {
        // Given
        settingsManager.isCloudSyncEnabled = false
        let base = try await sut.save(Conversation(modelId: "test", messages: [
            ChatMessage(role: .assistant, content: "Partial")
        ]))
        try await sut.delete(base.id)
        var interrupted = base
        interrupted.messages[0].responseInterruption = .backgroundTaskEnded

        // When / Then
        do {
            _ = try await sut.save(interrupted, expectedBase: base)
            XCTFail("A late interruption checkpoint must not restore deleted data")
        } catch {
            XCTAssertEqual(error as? CloudSyncError, .staleConversationRevision)
        }
        let reloaded = try await sut.loadLocal()
        XCTAssertTrue(reloaded.isEmpty)
    }
}
