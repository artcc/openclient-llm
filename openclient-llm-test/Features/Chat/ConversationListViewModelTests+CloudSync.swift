//
//  ConversationListViewModelTests+CloudSync.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 09/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

// MARK: - Tests - Cloud Sync

@MainActor
extension ConversationListViewModelTests {
    func test_send_refreshTapped_synchronizesBeforeReloadingConversations() async throws {
        // Given
        mockLoadConversations.result = .success([])
        mockFetchModels.result = .success([])
        sut.send(.viewAppeared)
        for _ in 0..<10 { await Task.yield() }
        let remoteConversation = Conversation(modelId: "gpt-4")
        mockLoadConversations.result = .success([remoteConversation])

        // When
        sut.send(.refreshTapped)
        await waitUntil {
            guard case .loaded(let loadedState) = self.sut.state else { return false }
            return self.mockSyncConversations.executeCallCount == 2
                && loadedState.conversations == [remoteConversation]
        }

        // Then
        XCTAssertEqual(mockSyncConversations.executeCallCount, 2)
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.conversations, [remoteConversation])
    }

    func test_conversationUpdateNotification_reloadsWithoutStartingSynchronization() async throws {
        // Given
        mockLoadConversations.result = .success([])
        mockFetchModels.result = .success([])
        sut.send(.viewAppeared)
        for _ in 0..<10 { await Task.yield() }
        let remoteConversation = Conversation(modelId: "gpt-4")
        mockLoadConversations.result = .success([remoteConversation])
        let folder = ConversationFolder(id: UUID(), name: "Renamed in another window", updatedAt: .now)
        mockFolders.snapshot = .init(folders: [folder], memberships: [
            .init(conversationId: remoteConversation.id, folderId: folder.id, updatedAt: .now)
        ])

        // When
        NotificationCenter.default.post(name: .conversationDidUpdate, object: nil)
        await waitUntil {
            guard case .loaded(let loadedState) = self.sut.state else { return false }
            return loadedState.conversations == [remoteConversation]
                && loadedState.folderName(for: remoteConversation.id) == folder.name
        }

        // Then
        XCTAssertEqual(mockSyncConversations.executeCallCount, 1)
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.conversations, [remoteConversation])
    }

    func test_send_viewAppeared_withPendingDownload_retriesSynchronizationOnce() async throws {
        // Given
        mockLoadConversations.result = .success([])
        mockFetchModels.result = .success([])
        mockSyncConversations.results = [.pendingDownload, .synchronized]
        mockSettingsManager.isCloudSyncEnabled = true

        // When
        sut.send(.viewAppeared)
        await waitUntil { self.mockSyncConversations.executeCallCount == 2 }

        // Then
        XCTAssertEqual(mockSyncConversations.executeCallCount, 2)
    }
}
