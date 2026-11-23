//
//  ConversationListViewModelTests.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 31/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class ConversationListViewModelTests: XCTestCase {
    // MARK: - Properties

    var sut: ConversationListViewModel!
    var mockLoadConversations: MockLoadConversationsUseCase!
    var mockDeleteConversation: MockDeleteConversationUseCase!
    var mockPinConversation: MockPinConversationUseCase!
    var mockUpdateTags: MockUpdateConversationTagsUseCase!
    var mockRenameConversation: MockRenameConversationUseCase!
    var mockFetchModels: MockFetchModelsUseCase!
    var mockSyncConversations: MockSyncConversationsUseCase!
    var mockSettingsManager: MockSettingsManager!
    var mockExportBackup: MockExportBackupUseCase!
    var mockImportConversations: MockImportConversationsUseCase!
    var mockFolders: ListFolderStoreDouble!

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()

        mockLoadConversations = MockLoadConversationsUseCase()
        mockDeleteConversation = MockDeleteConversationUseCase()
        mockPinConversation = MockPinConversationUseCase()
        mockUpdateTags = MockUpdateConversationTagsUseCase()
        mockRenameConversation = MockRenameConversationUseCase()
        mockFetchModels = MockFetchModelsUseCase()
        mockSyncConversations = MockSyncConversationsUseCase()
        mockSettingsManager = MockSettingsManager()
        mockExportBackup = MockExportBackupUseCase()
        mockImportConversations = MockImportConversationsUseCase()
        mockFolders = ListFolderStoreDouble()
        sut = makeViewModel()
    }

    func makeViewModel(state: ConversationListViewModel.State = .loading) -> ConversationListViewModel {
        ConversationListViewModel(
            state: state,
            loadConversationsUseCase: mockLoadConversations,
            deleteConversationUseCase: mockDeleteConversation,
            pinConversationUseCase: mockPinConversation,
            updateConversationTagsUseCase: mockUpdateTags,
            renameConversationUseCase: mockRenameConversation,
            fetchModelsUseCase: mockFetchModels,
            syncConversationsUseCase: mockSyncConversations,
            exportBackupUseCase: mockExportBackup,
            importConversationsUseCase: mockImportConversations,
            settingsManager: mockSettingsManager,
            folderRepository: mockFolders,
            cloudRetryDelays: [.zero]
        )
    }

    override func tearDown() async throws {
        sut = nil
        mockLoadConversations = nil
        mockDeleteConversation = nil
        mockPinConversation = nil
        mockUpdateTags = nil
        mockRenameConversation = nil
        mockFetchModels = nil
        mockSyncConversations = nil
        mockSettingsManager = nil
        mockExportBackup = nil
        mockImportConversations = nil
        mockFolders = nil

        try await super.tearDown()
    }

    // MARK: - Tests — Init

    func test_init_defaultState_isLoading() {
        // Then
        XCTAssertEqual(sut.state, .loading)
    }

    // MARK: - Tests — newConversationTapped

    func test_send_newConversationTapped_callsOnConversationSelected() async throws {
        // Given
        mockLoadConversations.result = .success([])
        mockFetchModels.result = .success([LLMModel(id: "gpt-4")])
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        var selectedConversation: Conversation?
        sut.onConversationSelected = { selectedConversation = $0 }

        // When
        sut.send(.newConversationTapped)

        // Then
        XCTAssertNotNil(selectedConversation)
        XCTAssertEqual(selectedConversation?.modelId, "gpt-4")
    }

    func test_send_newConversationTapped_usesSelectedModelFromSettings() async throws {
        // Given
        mockLoadConversations.result = .success([])
        mockFetchModels.result = .success([LLMModel(id: "gpt-4"), LLMModel(id: "llama3")])
        mockSettingsManager.selectedModelId = "llama3"
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        var selectedConversation: Conversation?
        sut.onConversationSelected = { selectedConversation = $0 }

        // When
        sut.send(.newConversationTapped)

        // Then
        XCTAssertEqual(selectedConversation?.modelId, "llama3")
    }

    func test_send_newConversationTapped_noModels_createsConversationWithEmptyModelId() async throws {
        // Given
        mockLoadConversations.result = .success([])
        mockFetchModels.result = .success([])
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        var selectedConversation: Conversation?
        sut.onConversationSelected = { selectedConversation = $0 }

        // When
        sut.send(.newConversationTapped)

        // Then
        XCTAssertNotNil(selectedConversation)
        XCTAssertEqual(selectedConversation?.modelId, "")
        XCTAssertTrue(selectedConversation?.messages.isEmpty ?? false)
    }

    // MARK: - Tests — conversationTapped

    func test_send_conversationTapped_selectsConversation() async throws {
        // Given
        let conversation = Conversation(modelId: "gpt-4")
        mockLoadConversations.result = .success([conversation])
        mockFetchModels.result = .success([LLMModel(id: "gpt-4")])
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        var selectedConversation: Conversation?
        sut.onConversationSelected = { selectedConversation = $0 }

        // When
        sut.send(.conversationTapped(conversation))

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.selectedConversation, conversation)
        XCTAssertEqual(selectedConversation, conversation)
    }

    // MARK: - Tests — deleteConversation

    func test_send_deleteConversation_removesFromList() async throws {
        // Given
        let conversation = Conversation(modelId: "gpt-4")
        mockLoadConversations.result = .success([conversation])
        mockFetchModels.result = .success([])
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        // When
        sut.send(.deleteConversation(conversation.id))
        await waitUntil {
            guard case .loaded(let loadedState) = self.sut.state else { return false }
            return loadedState.conversations.isEmpty
        }

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertTrue(loadedState.conversations.isEmpty)
        XCTAssertEqual(mockDeleteConversation.deletedIds, [conversation.id])
    }

    func test_send_deleteConversation_clearsSelectionIfSelected() async throws {
        // Given
        let conversation = Conversation(modelId: "gpt-4")
        mockLoadConversations.result = .success([conversation])
        mockFetchModels.result = .success([])
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        sut.send(.conversationTapped(conversation))

        var deselectedCalled = false
        sut.onConversationSelected = { conversation in
            if conversation == nil { deselectedCalled = true }
        }

        // When
        sut.send(.deleteConversation(conversation.id))
        await waitUntil {
            guard case .loaded(let loadedState) = self.sut.state else { return false }
            return loadedState.selectedConversation == nil
        }

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertNil(loadedState.selectedConversation)
        XCTAssertTrue(deselectedCalled)
    }

    func test_send_deleteConversation_withError_setsErrorMessage() async throws {
        // Given
        let conversation = Conversation(modelId: "gpt-4")
        mockLoadConversations.result = .success([conversation])
        mockFetchModels.result = .success([])
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        mockDeleteConversation.error = NSError(domain: "test", code: 1)

        // When
        sut.send(.deleteConversation(conversation.id))
        await waitUntil {
            guard case .loaded(let loadedState) = self.sut.state else { return false }
            return loadedState.errorMessage != nil
        }

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        // Conversation should still be in the list since delete failed
        XCTAssertEqual(loadedState.conversations.count, 1)
        XCTAssertNotNil(loadedState.errorMessage)
    }

    // MARK: - Tests — refresh

    func test_refresh_reloadsConversations() async throws {
        // Given
        mockLoadConversations.result = .success([])
        mockFetchModels.result = .success([])
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        let newConversation = Conversation(modelId: "gpt-4")
        mockLoadConversations.result = .success([newConversation])

        // When
        sut.refresh()
        await waitUntil {
            guard case .loaded(let loadedState) = self.sut.state else { return false }
            return loadedState.conversations.count == 1
        }

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.conversations.count, 1)
    }

    // MARK: - Tests — searchChanged

    func test_send_searchChanged_filtersByTitle() async throws {
        // Given
        let conversations = [
            Conversation(title: "Swift coding", modelId: "gpt-4"),
            Conversation(title: "Python tips", modelId: "gpt-4"),
            Conversation(title: "SwiftUI views", modelId: "llama3")
        ]
        mockLoadConversations.result = .success(conversations)
        mockFetchModels.result = .success([])
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        // When
        sut.send(.searchChanged("Swift"))

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.filteredConversations.count, 2)
        XCTAssertEqual(loadedState.searchQuery, "Swift")
    }

    func test_send_searchChanged_filtersByMessageContent() async throws {
        // Given
        let conversations = [
            Conversation(
                title: "Chat 1",
                modelId: "gpt-4",
                messages: [ChatMessage(role: .user, content: "Tell me about quantum physics")]
            ),
            Conversation(
                title: "Chat 2",
                modelId: "gpt-4",
                messages: [ChatMessage(role: .user, content: "Write a poem")]
            )
        ]
        mockLoadConversations.result = .success(conversations)
        mockFetchModels.result = .success([])
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        // When
        sut.send(.searchChanged("quantum"))

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.filteredConversations.count, 1)
        XCTAssertEqual(loadedState.filteredConversations.first?.title, "Chat 1")
    }

    func test_send_searchChanged_withEmptyQuery_showsAll() async throws {
        // Given
        let conversations = [
            Conversation(title: "Chat 1", modelId: "gpt-4"),
            Conversation(title: "Chat 2", modelId: "gpt-4")
        ]
        mockLoadConversations.result = .success(conversations)
        mockFetchModels.result = .success([])
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        sut.send(.searchChanged("Chat 1"))

        // When
        sut.send(.searchChanged(""))

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.filteredConversations.count, 2)
    }

    func test_send_searchChanged_noMatch_returnsEmpty() async throws {
        // Given
        let conversations = [
            Conversation(title: "Chat 1", modelId: "gpt-4"),
            Conversation(title: "Chat 2", modelId: "gpt-4")
        ]
        mockLoadConversations.result = .success(conversations)
        mockFetchModels.result = .success([])
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        // When
        sut.send(.searchChanged("nonexistent"))

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertTrue(loadedState.filteredConversations.isEmpty)
    }
}

// MARK: - Helpers

extension ConversationListViewModelTests {
    func waitUntil(
        _ condition: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<100 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Condition was not satisfied", file: file, line: line)
    }
}
