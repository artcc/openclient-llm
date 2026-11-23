//
//  ConversationListViewModelTests+Loading.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 09/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Observation
import XCTest
@testable import openclient_llm

// MARK: - Tests - Loading

@MainActor
extension ConversationListViewModelTests {
    func test_send_viewAppeared_loadsConversations() async throws {
        // Given
        let conversations = [
            Conversation(modelId: "gpt-4", messages: [ChatMessage(role: .user, content: "Hi")]),
            Conversation(modelId: "llama3")
        ]
        mockLoadConversations.result = .success(conversations)
        mockFetchModels.result = .success([LLMModel(id: "gpt-4")])
        let modelsLoaded = expectation(description: "Available models loaded")

        // When
        sut.send(.viewAppeared)
        Self.observeLoadedState(sut, expectation: modelsLoaded) { !$0.availableModels.isEmpty }
        await fulfillment(of: [modelsLoaded], timeout: 2)

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.conversations.count, 2)
        XCTAssertEqual(loadedState.availableModels.count, 1)
        XCTAssertNil(loadedState.errorMessage)
    }

    func test_send_viewAppeared_loadsLocallyBeforeSyncing() async throws {
        // Given
        let conversations = [Conversation(modelId: "gpt-4")]
        mockLoadConversations.result = .success(conversations)
        mockFetchModels.result = .success([])
        mockSyncConversations.result = .synchronized

        // When
        sut.send(.viewAppeared)
        for _ in 0..<10 { await Task.yield() }

        // Then
        XCTAssertEqual(mockLoadConversations.executeLocallyCallCount, 2)
        XCTAssertEqual(mockSyncConversations.executeCallCount, 1)
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.conversations, conversations)
    }

    func test_send_viewAppeared_whenHistoryReadFails_preservesErrorAndLoadsSelectedFolder() async throws {
        // Given
        let folder = ConversationFolder(id: UUID(), name: "Work", updatedAt: .now)
        mockFolders.snapshot = .init(folders: [folder], memberships: [])
        mockLoadConversations.result = .failure(NSError(domain: "test", code: 1))
        sut.setFolderScope(.folder(folder.id))
        let foldersLoaded = expectation(description: "Folder metadata available")

        // When
        sut.send(.viewAppeared)
        Self.observeLoadedState(sut, expectation: foldersLoaded) { $0.hasLoadedFolders }
        await fulfillment(of: [foldersLoaded], timeout: 2)

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertTrue(loadedState.conversations.isEmpty)
        XCTAssertNotNil(loadedState.errorMessage)
        XCTAssertEqual(loadedState.folders, [folder])
        XCTAssertEqual(loadedState.folderScope, .folder(folder.id))
    }

    func test_send_viewAppeared_withModelsError_stillLoadsConversations() async throws {
        // Given
        let conversations = [Conversation(modelId: "gpt-4")]
        mockLoadConversations.result = .success(conversations)
        mockFetchModels.result = .failure(NSError(domain: "test", code: 1))

        // When
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.conversations.count, 1)
        XCTAssertTrue(loadedState.availableModels.isEmpty)
    }
}

// MARK: - Private

private extension ConversationListViewModelTests {
    static func observeLoadedState(
        _ sut: ConversationListViewModel,
        expectation: XCTestExpectation,
        matching: @escaping @MainActor @Sendable (ConversationListViewModel.LoadedState) -> Bool
    ) {
        if case .loaded(let loadedState) = sut.state, matching(loadedState) {
            expectation.fulfill()
            return
        }
        withObservationTracking {
            _ = sut.state
        } onChange: { [weak sut] in
            Task { @MainActor in
                guard let sut else { return }
                observeLoadedState(sut, expectation: expectation, matching: matching)
            }
        }
    }
}
