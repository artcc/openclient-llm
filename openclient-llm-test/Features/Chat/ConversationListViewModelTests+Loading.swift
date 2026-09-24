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
        Self.observeModelsLoaded(sut, expectation: modelsLoaded)
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

    func test_send_viewAppeared_withError_setsErrorMessage() async throws {
        // Given
        mockLoadConversations.result = .failure(NSError(domain: "test", code: 1))
        mockFetchModels.result = .success([])

        // When
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertTrue(loadedState.conversations.isEmpty)
        XCTAssertNotNil(loadedState.errorMessage)
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
    static func observeModelsLoaded(_ sut: ConversationListViewModel, expectation: XCTestExpectation) {
        if case .loaded(let loadedState) = sut.state, !loadedState.availableModels.isEmpty {
            expectation.fulfill()
            return
        }
        withObservationTracking {
            _ = sut.state
        } onChange: { [weak sut] in
            Task { @MainActor in
                guard let sut else { return }
                observeModelsLoaded(sut, expectation: expectation)
            }
        }
    }
}
