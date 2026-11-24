//
//  ChatViewModelTests+Persistence.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 31/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

// MARK: - Tests — Conversation persistence

@MainActor
extension ChatViewModelTests {
    func test_persistConversation_contextualDraft_retriesPlacementUntilFirstSave() async {
        let folderID = UUID()
        let draft = Conversation(modelId: "model")
        sut = ChatViewModel(
            initialFolderID: folderID,
            state: .loaded(.init(conversation: draft)),
            saveConversationUseCase: mockSaveConversation,
            settingsManager: MockSettingsManager()
        )
        mockSaveConversation.failureAtCall = 1

        let failed = await sut.persistConversation()
        let retried = await sut.persistConversation()
        let updated = await sut.persistConversation()

        XCTAssertFalse(failed)
        XCTAssertTrue(retried)
        XCTAssertTrue(updated)
        XCTAssertEqual(mockSaveConversation.creationPlacements, [.folder(folderID), .folder(folderID), nil])
    }

    func test_persistConversation_selectingExistingChat_discardsDraftDestination() async {
        let draft = Conversation(modelId: "model")
        let folderID = UUID()
        let existing = Conversation(modelId: "model")
        sut = ChatViewModel(
            initialFolderID: folderID,
            state: .loaded(.init(conversation: draft)),
            saveConversationUseCase: mockSaveConversation,
            settingsManager: MockSettingsManager()
        )

        sut.send(.systemPromptChanged("First checkpoint"))
        sut.send(.conversationLoaded(existing))
        let didSave = await sut.persistConversation()

        XCTAssertTrue(didSave)
        XCTAssertEqual(mockSaveConversation.savedConversations.map(\.id), [draft.id, existing.id])
        XCTAssertEqual(mockSaveConversation.creationPlacements, [.folder(folderID), nil])
    }

    func test_send_sendTapped_createsConversation() async throws {
        // Given
        mockFetchModels.result = .success([LLMModel(id: "gpt-4")])
        mockStreamMessage.chunks = [.token("Hello")]
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        sut.send(.inputChanged("Hi"))

        // When
        sut.send(.sendTapped)
        try await Task.sleep(for: .milliseconds(200))

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertNotNil(loadedState.conversation)
        XCTAssertEqual(loadedState.conversation?.modelId, "gpt-4")
    }

    func test_send_sendTapped_persistsConversation() async throws {
        // Given
        mockFetchModels.result = .success([LLMModel(id: "gpt-4")])
        mockStreamMessage.chunks = [.token("Response")]
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        sut.send(.inputChanged("Hello"))

        // When
        sut.send(.sendTapped)
        try await Task.sleep(for: .milliseconds(200))

        // Then
        XCTAssertFalse(mockSaveConversation.savedConversations.isEmpty)
    }

    func test_send_sendTapped_synchronizesConversationMessagesWithState() async throws {
        // Given
        mockFetchModels.result = .success([LLMModel(id: "gpt-4")])
        mockStreamMessage.chunks = [.token("Response")]
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        sut.send(.inputChanged("Hello"))

        // When
        sut.send(.sendTapped)
        try await Task.sleep(for: .milliseconds(200))

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.conversation?.messages, loadedState.messages)
        XCTAssertEqual(mockSaveConversation.savedConversations.last?.messages, loadedState.messages)
    }

    func test_send_conversationLoaded_restoresMessages() async throws {
        // Given
        mockFetchModels.result = .success([LLMModel(id: "gpt-4")])
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        let messages = [
            ChatMessage(role: .user, content: "Hello"),
            ChatMessage(role: .assistant, content: "Hi there!")
        ]
        let conversation = Conversation(
            modelId: "gpt-4",
            systemPrompt: "Be helpful",
            messages: messages
        )

        // When
        sut.send(.conversationLoaded(conversation))

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.messages.count, 2)
        XCTAssertEqual(loadedState.systemPrompt, "Be helpful")
        XCTAssertNotNil(loadedState.conversation)
        XCTAssertEqual(loadedState.inputRevision, 1)
    }

    func test_send_conversationLoaded_duringStreaming_preservesPreviousConversation() async throws {
        // Given
        mockFetchModels.result = .success([LLMModel(id: "gpt-4")])
        mockStreamMessage.chunks = [.token("Delayed response")]
        mockStreamMessage.tokenDelay = .milliseconds(300)
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))
        sut.send(.inputChanged("First chat"))
        sut.send(.sendTapped)

        guard case .loaded(let streamingState) = sut.state,
              let previousConversation = streamingState.conversation else {
            XCTFail("Expected a streaming conversation")
            return
        }
        let selectedConversation = Conversation(
            modelId: "gpt-4",
            messages: [ChatMessage(role: .user, content: "Second chat")]
        )

        // When
        sut.send(.conversationLoaded(selectedConversation))
        await waitUntil {
            self.mockSaveConversation.savedConversations.contains { $0.id == previousConversation.id }
        }

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.conversation?.id, selectedConversation.id)
        XCTAssertEqual(loadedState.messages, selectedConversation.messages)
        XCTAssertFalse(loadedState.isStreaming)
        XCTAssertTrue(mockSaveConversation.savedConversations.contains { $0.id == previousConversation.id })
        XCTAssertFalse(mockSaveConversation.savedConversations.contains { $0.id == selectedConversation.id })
    }

    func test_send_sendTapped_withLongHistory_limitsRequestHistory() async throws {
        // Given
        mockFetchModels.result = .success([LLMModel(id: "gpt-4")])
        let history = (0..<60).map { ChatMessage(role: .user, content: "Message \($0)") }
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))
        sut.send(.conversationLoaded(Conversation(modelId: "gpt-4", messages: history)))
        sut.send(.inputChanged("Latest message"))

        // When
        sut.send(.sendTapped)
        try await Task.sleep(for: .milliseconds(200))

        // Then
        XCTAssertEqual(mockStreamMessage.receivedMessages.last?.count, 50)
        XCTAssertEqual(mockStreamMessage.receivedMessages.last?.last?.content, "Latest message")
    }

    // MARK: - Tests — System prompt

    func test_send_systemPromptChanged_updatesState() async throws {
        // Given
        mockFetchModels.result = .success([LLMModel(id: "gpt-4")])
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        // When
        sut.send(.systemPromptChanged("You are a pirate"))

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.systemPrompt, "You are a pirate")
    }

    // MARK: - Tests — Attachments

    func test_send_attachmentAdded_addsToState() async throws {
        // Given
        mockFetchModels.result = .success([LLMModel(id: "gpt-4")])
        mockAttachmentRepository.saveResult = .success("Attachments/pending/test-id.jpg")
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        // When
        sut.send(.attachmentAdded(data: Data([0xFF, 0xD8]), fileName: "test.jpg", type: .image))
        try await Task.sleep(for: .milliseconds(50))

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.pendingAttachments.count, 1)
        XCTAssertEqual(loadedState.pendingAttachments.first?.fileName, "test.jpg")
    }

    func test_send_attachmentRemoved_removesFromState() async throws {
        // Given
        mockFetchModels.result = .success([LLMModel(id: "gpt-4")])
        mockAttachmentRepository.saveResult = .success("Attachments/pending/test-id.jpg")
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        sut.send(.attachmentAdded(data: Data([0xFF, 0xD8]), fileName: "test.jpg", type: .image))
        try await Task.sleep(for: .milliseconds(50))

        guard case .loaded(let loadedState) = sut.state,
              let addedAttachment = loadedState.pendingAttachments.first else {
            XCTFail("Expected loaded state with attachment")
            return
        }

        // When
        sut.send(.attachmentRemoved(addedAttachment.id))

        // Then
        guard case .loaded(let finalState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertTrue(finalState.pendingAttachments.isEmpty)
    }

    func test_send_sendTapped_clearsAttachments() async throws {
        // Given
        mockFetchModels.result = .success([LLMModel(id: "gpt-4")])
        mockStreamMessage.chunks = [.token("Response")]
        mockAttachmentRepository.saveResult = .success("Attachments/pending/test-id.jpg")
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        sut.send(.attachmentAdded(data: Data([0xFF, 0xD8]), fileName: "test.jpg", type: .image))
        try await Task.sleep(for: .milliseconds(50))

        sut.send(.inputChanged("Describe this image"))

        // When
        sut.send(.sendTapped)

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertTrue(loadedState.pendingAttachments.isEmpty)
        XCTAssertFalse(loadedState.messages.first(where: { $0.role == .user })?.attachments.isEmpty ?? true)
    }

    // MARK: - Tests — Conversation at init

    func test_init_withConversation_loadsConversationAfterModels() async throws {
        // Given
        let models = [LLMModel(id: "gpt-4"), LLMModel(id: "llama3")]
        let messages = [
            ChatMessage(role: .user, content: "Hello"),
            ChatMessage(role: .assistant, content: "Hi!")
        ]
        let conversation = Conversation(
            modelId: "llama3",
            systemPrompt: "Be helpful",
            messages: messages
        )

        mockFetchModels.result = .success(models)
        sut = ChatViewModel(
            conversation: conversation,
            fetchModelsUseCase: mockFetchModels,
            streamMessageUseCase: mockStreamMessage,
            saveConversationUseCase: mockSaveConversation,
            getChatPreferencesUseCase: mockGetChatPreferences,
            fetchMCPToolsUseCase: MockFetchMCPToolsUseCase(),
            getConversationStartersUseCase: mockGetConversationStarters
        )

        // When
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.messages.count, 2)
        XCTAssertEqual(loadedState.conversation?.id, conversation.id)
        XCTAssertEqual(loadedState.selectedModel?.id, "llama3")
        XCTAssertEqual(loadedState.systemPrompt, "Be helpful")
        XCTAssertTrue(loadedState.conversationStarters.isEmpty)
    }

    func test_init_withConversation_loadsConversationEvenOnModelError() async throws {
        // Given
        let messages = [ChatMessage(role: .user, content: "Hello")]
        let conversation = Conversation(modelId: "gpt-4", messages: messages)

        mockFetchModels.result = .failure(APIError.serverUnreachable)
        sut = ChatViewModel(
            conversation: conversation,
            fetchModelsUseCase: mockFetchModels,
            streamMessageUseCase: mockStreamMessage,
            saveConversationUseCase: mockSaveConversation,
            getChatPreferencesUseCase: mockGetChatPreferences,
            fetchMCPToolsUseCase: MockFetchMCPToolsUseCase(),
            getConversationStartersUseCase: mockGetConversationStarters
        )

        // When
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.messages.count, 1)
        XCTAssertNotNil(loadedState.conversation)
        XCTAssertNotNil(loadedState.errorMessage)
    }

    // MARK: - Tests — Conversation auto-title

    func test_send_sendTapped_setsConversationTitleFromFirstMessage() async throws {
        // Given
        mockFetchModels.result = .success([LLMModel(id: "gpt-4")])
        mockStreamMessage.chunks = [.token("Response")]
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        sut.send(.inputChanged("What is quantum computing?"))

        // When
        sut.send(.sendTapped)
        try await Task.sleep(for: .milliseconds(200))

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.conversation?.title, "What is quantum computing?")
    }

    // MARK: - Tests — Model parameters

    func test_send_modelParametersChanged_updatesState() async throws {
        // Given
        mockFetchModels.result = .success([LLMModel(id: "gpt-4")])
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        // When
        let parameters = ModelParameters(temperature: 0.5, maxTokens: 2048, topP: 0.9)
        sut.send(.modelParametersChanged(parameters))

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.modelParameters.temperature, 0.5)
        XCTAssertEqual(loadedState.modelParameters.maxTokens, 2048)
        XCTAssertEqual(loadedState.modelParameters.topP, 0.9)
    }

    func test_send_modelParametersChanged_persistsConversation() async throws {
        // Given
        mockFetchModels.result = .success([LLMModel(id: "gpt-4")])
        mockStreamMessage.chunks = [.token("Hello")]
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        // Create a conversation first
        sut.send(.inputChanged("Hi"))
        sut.send(.sendTapped)
        try await Task.sleep(for: .milliseconds(200))

        let savedCountBefore = mockSaveConversation.savedConversations.count

        // When
        let parameters = ModelParameters(temperature: 1.2)
        sut.send(.modelParametersChanged(parameters))
        await waitUntil { self.mockSaveConversation.savedConversations.count > savedCountBefore }

        // Then
        XCTAssertGreaterThan(mockSaveConversation.savedConversations.count, savedCountBefore)
        let lastSaved = mockSaveConversation.savedConversations.last
        XCTAssertEqual(lastSaved?.modelParameters.temperature, 1.2)
    }

    func test_send_conversationLoaded_restoresModelParameters() async throws {
        // Given
        mockFetchModels.result = .success([LLMModel(id: "gpt-4")])
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        let parameters = ModelParameters(temperature: 0.3, maxTokens: 1024)
        let conversation = Conversation(
            modelId: "gpt-4",
            modelParameters: parameters
        )

        // When
        sut.send(.conversationLoaded(conversation))

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.modelParameters.temperature, 0.3)
        XCTAssertEqual(loadedState.modelParameters.maxTokens, 1024)
    }

    func test_modelParameters_default_hasNoCustomValues() {
        // Given
        let parameters = ModelParameters.default

        // Then
        XCTAssertFalse(parameters.hasCustomValues)
        XCTAssertNil(parameters.temperature)
        XCTAssertNil(parameters.maxTokens)
        XCTAssertNil(parameters.topP)
    }

    func test_modelParameters_withValues_hasCustomValues() {
        // Given
        let parameters = ModelParameters(temperature: 0.7)

        // Then
        XCTAssertTrue(parameters.hasCustomValues)
    }
}
