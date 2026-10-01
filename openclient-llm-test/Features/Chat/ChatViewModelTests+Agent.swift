//
//  ChatViewModelTests+Agent.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 05/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

// MARK: - Tests — Agent Mode

@MainActor
extension ChatViewModelTests {
    func test_sendMessage_withFunctionCallingModel_andWebSearch_usesAgentUseCase() async throws {
        // Given
        let mockAgent = MockAgentStreamUseCase()
        let toolCall = ToolCall(
            id: "tool-1",
            type: "function",
            function: ToolCallFunction(name: "web_search", arguments: "{}")
        )
        mockAgent.events = [
            .toolCallStarted(toolCall),
            .toolCallCompleted(toolCallId: toolCall.id, result: "Result", searchResults: nil),
            .token("Agent"),
            .token(" answer")
        ]
        let background = MockStreamingBackgroundUseCase()
        let notification = MockNotifyStreamingCompletedUseCase()
        let modelWithFunctionCalling = LLMModel(id: "gpt-4", capabilities: [.functionCalling])
        mockFetchModels.result = .success([modelWithFunctionCalling])

        let sutWithAgent = ChatViewModel(
            fetchModelsUseCase: mockFetchModels,
            streamMessageUseCase: mockStreamMessage,
            agentStreamUseCase: mockAgent,
            webSearchUseCase: mockWebSearch,
            saveConversationUseCase: mockSaveConversation,
            exportConversationUseCase: mockExportConversation,
            branchConversationUseCase: mockBranchConversation,
            getChatPreferencesUseCase: mockGetChatPreferences,
            fetchMCPToolsUseCase: MockFetchMCPToolsUseCase(),
            getConversationStartersUseCase: mockGetConversationStarters,
            streamingBackgroundUseCase: background,
            notifyStreamingCompletedUseCase: notification
        )

        sutWithAgent.send(.viewAppeared)
        await waitUntil {
            if case .loaded = sutWithAgent.state { return true }
            return false
        }

        // Enable web search
        sutWithAgent.send(.webSearchToggled)
        sutWithAgent.send(.inputChanged("search something"))
        let completed = expectation(description: "Background task completed")
        background.onEnd = { _ in completed.fulfill() }

        // When
        sutWithAgent.send(.sendTapped)
        await fulfillment(of: [completed], timeout: 1)

        // Then
        guard case .loaded(let loadedState) = sutWithAgent.state else {
            XCTFail("Expected loaded state")
            return
        }
        let assistantMessages = loadedState.messages.filter { $0.role == .assistant }
        XCTAssertEqual(assistantMessages.last?.content, "Agent answer")
        XCTAssertTrue(background.phases.contains(.usingTools))
        XCTAssertEqual(background.completionResults, [true])
        XCTAssertEqual(notification.completionCallCount, 1)
    }

    func test_sendMessage_withFunctionCallingModel_webSearchDisabled_usesAgentStreaming() async throws {
        // Given — model has functionCalling; agent mode is entered regardless of web search toggle
        let mockAgent = MockAgentStreamUseCase()
        mockAgent.events = [.token("Agent answer")]
        mockStreamMessage.chunks = [.token("Should not appear")]
        let modelWithFunctionCalling = LLMModel(id: "gpt-4", capabilities: [.functionCalling])
        mockFetchModels.result = .success([modelWithFunctionCalling])

        let sutWithAgent = ChatViewModel(
            fetchModelsUseCase: mockFetchModels,
            streamMessageUseCase: mockStreamMessage,
            agentStreamUseCase: mockAgent,
            webSearchUseCase: mockWebSearch,
            saveConversationUseCase: mockSaveConversation,
            exportConversationUseCase: mockExportConversation,
            branchConversationUseCase: mockBranchConversation,
            getChatPreferencesUseCase: mockGetChatPreferences,
            fetchMCPToolsUseCase: MockFetchMCPToolsUseCase(),
            getConversationStartersUseCase: mockGetConversationStarters,
            streamingBackgroundUseCase: MockStreamingBackgroundUseCase(),
            notifyStreamingCompletedUseCase: MockNotifyStreamingCompletedUseCase()
        )

        sutWithAgent.send(.viewAppeared)
        await waitUntil {
            if case .loaded = sutWithAgent.state { return true }
            return false
        }

        // Web search NOT enabled
        sutWithAgent.send(.inputChanged("regular message"))

        // When
        sutWithAgent.send(.sendTapped)
        try await Task.sleep(for: .milliseconds(200))

        // Then — agent is used because model has functionCalling, even without web search
        guard case .loaded(let loadedState) = sutWithAgent.state else {
            XCTFail("Expected loaded state")
            return
        }
        let assistantMessages = loadedState.messages.filter { $0.role == .assistant }
        XCTAssertFalse(assistantMessages.isEmpty)
        let lastAssistant = assistantMessages.last
        XCTAssertEqual(lastAssistant?.content, "Agent answer")
    }

    func test_sendMessage_agentToken_publishesFirstTokenWhileResponseIsPending() async throws {
        // Given
        let mockAgent = MockAgentStreamUseCase()
        mockAgent.events = [.token("Agent")]
        mockAgent.waitsForCancellation = true
        let modelWithFunctionCalling = LLMModel(id: "gpt-4", capabilities: [.functionCalling])
        mockFetchModels.result = .success([modelWithFunctionCalling])
        let sutWithAgent = ChatViewModel(
            fetchModelsUseCase: mockFetchModels,
            streamMessageUseCase: mockStreamMessage,
            agentStreamUseCase: mockAgent,
            webSearchUseCase: mockWebSearch,
            saveConversationUseCase: mockSaveConversation,
            exportConversationUseCase: mockExportConversation,
            branchConversationUseCase: mockBranchConversation,
            getChatPreferencesUseCase: mockGetChatPreferences,
            fetchMCPToolsUseCase: MockFetchMCPToolsUseCase(),
            getConversationStartersUseCase: mockGetConversationStarters,
            streamingBackgroundUseCase: MockStreamingBackgroundUseCase(),
            notifyStreamingCompletedUseCase: MockNotifyStreamingCompletedUseCase()
        )
        sutWithAgent.send(.viewAppeared)
        await waitUntil {
            if case .loaded = sutWithAgent.state { return true }
            return false
        }

        // When
        sutWithAgent.send(.inputChanged("Tell me a story"))
        sutWithAgent.send(.sendTapped)
        await waitUntil {
            guard case .loaded(let loadedState) = sutWithAgent.state else { return false }
            return loadedState.messages.last?.content == "Agent"
        }

        // Then
        guard case .loaded(let loadedState) = sutWithAgent.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.streamingRevision, 1)
        XCTAssertTrue(sutWithAgent.streamingUpdateBuffer.updates.isEmpty)
        XCTAssertTrue(loadedState.isStreaming)
        sutWithAgent.send(.stopStreamingTapped)
    }

    func test_sendMessage_noCapabilitiesModel_andWebSearch_usesRegularStreaming() async throws {
        // Given — model without any capabilities (no functionCalling)
        let mockAgent = MockAgentStreamUseCase()
        mockAgent.events = [.token("Should not appear")]
        mockStreamMessage.chunks = [.token("Regular response")]
        let modelWithoutCapabilities = LLMModel(id: "llama3", capabilities: [])
        mockFetchModels.result = .success([modelWithoutCapabilities])

        let sutWithAgent = ChatViewModel(
            fetchModelsUseCase: mockFetchModels,
            streamMessageUseCase: mockStreamMessage,
            agentStreamUseCase: mockAgent,
            webSearchUseCase: mockWebSearch,
            saveConversationUseCase: mockSaveConversation,
            exportConversationUseCase: mockExportConversation,
            branchConversationUseCase: mockBranchConversation,
            getChatPreferencesUseCase: mockGetChatPreferences,
            fetchMCPToolsUseCase: MockFetchMCPToolsUseCase(),
            getConversationStartersUseCase: mockGetConversationStarters,
            streamingBackgroundUseCase: MockStreamingBackgroundUseCase(),
            notifyStreamingCompletedUseCase: MockNotifyStreamingCompletedUseCase()
        )

        sutWithAgent.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        // Enable web search
        sutWithAgent.send(.webSearchToggled)
        sutWithAgent.send(.inputChanged("news about AI"))

        // When
        sutWithAgent.send(.sendTapped)
        try await Task.sleep(for: .milliseconds(200))

        // Then — falls through to regular streaming, does NOT call web search or agent
        guard case .loaded(let loadedState) = sutWithAgent.state else {
            XCTFail("Expected loaded state")
            return
        }
        let assistantMessages = loadedState.messages.filter { $0.role == .assistant }
        XCTAssertFalse(assistantMessages.isEmpty)
        let lastAssistant = assistantMessages.last
        XCTAssertEqual(lastAssistant?.content, "Regular response")
        XCTAssertEqual(
            mockWebSearch.executeCallCount,
            0,
            "Web search should NOT be called for models without capabilities"
        )
    }

    func test_applyAgentEvent_token_appendsToAssistantMessage() {
        // Given
        let assistantId = UUID()
        var loadedState = ChatViewModel.LoadedState()
        loadedState.messages = [ChatMessage(id: assistantId, role: .assistant, content: "")]

        // When
        let viewModel = ChatViewModel(
            fetchModelsUseCase: mockFetchModels,
            streamMessageUseCase: mockStreamMessage,
            agentStreamUseCase: MockAgentStreamUseCase(),
            webSearchUseCase: mockWebSearch,
            saveConversationUseCase: mockSaveConversation,
            exportConversationUseCase: mockExportConversation,
            branchConversationUseCase: mockBranchConversation,
            getChatPreferencesUseCase: mockGetChatPreferences,
            fetchMCPToolsUseCase: MockFetchMCPToolsUseCase(),
            getConversationStartersUseCase: mockGetConversationStarters,
            streamingBackgroundUseCase: MockStreamingBackgroundUseCase(),
            notifyStreamingCompletedUseCase: MockNotifyStreamingCompletedUseCase()
        )
        viewModel.applyAgentEvent(.token("Hello "), to: &loadedState, assistantMessageId: assistantId)
        viewModel.applyAgentEvent(.token("world"), to: &loadedState, assistantMessageId: assistantId)

        // Then
        XCTAssertEqual(loadedState.messages.first?.content, "Hello world")
    }

    func test_applyAgentEvent_toolCallStarted_setsIsSearchingWeb() {
        // Given
        var loadedState = ChatViewModel.LoadedState()
        loadedState.isSearchingWeb = false
        let toolCall = ToolCall(
            id: "c1",
            type: "function",
            function: ToolCallFunction(name: "web_search", arguments: "{}")
        )
        let viewModel = ChatViewModel(
            fetchModelsUseCase: mockFetchModels,
            streamMessageUseCase: mockStreamMessage,
            agentStreamUseCase: MockAgentStreamUseCase(),
            webSearchUseCase: mockWebSearch,
            saveConversationUseCase: mockSaveConversation,
            exportConversationUseCase: mockExportConversation,
            branchConversationUseCase: mockBranchConversation,
            getChatPreferencesUseCase: mockGetChatPreferences,
            fetchMCPToolsUseCase: MockFetchMCPToolsUseCase(),
            getConversationStartersUseCase: mockGetConversationStarters,
            streamingBackgroundUseCase: MockStreamingBackgroundUseCase(),
            notifyStreamingCompletedUseCase: MockNotifyStreamingCompletedUseCase()
        )

        // When
        viewModel.applyAgentEvent(.toolCallStarted(toolCall), to: &loadedState, assistantMessageId: UUID())

        // Then
        XCTAssertTrue(loadedState.isSearchingWeb)
    }

    func test_applyAgentEvent_toolCallCompleted_clearsIsSearchingWeb() {
        // Given
        var loadedState = ChatViewModel.LoadedState()
        loadedState.isSearchingWeb = true
        let viewModel = ChatViewModel(
            fetchModelsUseCase: mockFetchModels,
            streamMessageUseCase: mockStreamMessage,
            agentStreamUseCase: MockAgentStreamUseCase(),
            webSearchUseCase: mockWebSearch,
            saveConversationUseCase: mockSaveConversation,
            exportConversationUseCase: mockExportConversation,
            branchConversationUseCase: mockBranchConversation,
            getChatPreferencesUseCase: mockGetChatPreferences,
            fetchMCPToolsUseCase: MockFetchMCPToolsUseCase(),
            getConversationStartersUseCase: mockGetConversationStarters,
            streamingBackgroundUseCase: MockStreamingBackgroundUseCase(),
            notifyStreamingCompletedUseCase: MockNotifyStreamingCompletedUseCase()
        )

        // When
        viewModel.applyAgentEvent(
            .toolCallCompleted(toolCallId: "c1", result: "results", searchResults: nil),
            to: &loadedState,
            assistantMessageId: UUID()
        )

        // Then
        XCTAssertFalse(loadedState.isSearchingWeb)
    }

    func test_applyAgentEvent_transcriptAppended_insertsBeforeFinalAssistant() {
        // Given
        let user = ChatMessage(role: .user, content: "Question")
        let finalAssistant = ChatMessage(role: .assistant, content: "")
        let toolAssistant = ChatMessage(role: .assistant, content: "Tool call")
        let tool = ChatMessage(role: .tool, content: "Result")
        var loadedState = ChatViewModel.LoadedState(messages: [user, finalAssistant])

        // When
        sut.applyAgentEvent(
            .transcriptAppended([toolAssistant, tool]),
            to: &loadedState,
            assistantMessageId: finalAssistant.id
        )

        // Then
        XCTAssertEqual(loadedState.messages.map(\.id), [user.id, toolAssistant.id, tool.id, finalAssistant.id])
    }

    func test_applyAgentEvent_agentError_setsErrorMessage() async throws {
        // Given
        let mockAgent = MockAgentStreamUseCase()
        mockAgent.error = APIError.networkError("Timeout")
        let background = MockStreamingBackgroundUseCase()
        let notification = MockNotifyStreamingCompletedUseCase()
        let modelWithFC = LLMModel(id: "gpt-4", capabilities: [.functionCalling])
        mockFetchModels.result = .success([modelWithFC])

        let sutWithAgent = ChatViewModel(
            fetchModelsUseCase: mockFetchModels,
            streamMessageUseCase: mockStreamMessage,
            agentStreamUseCase: mockAgent,
            webSearchUseCase: mockWebSearch,
            saveConversationUseCase: mockSaveConversation,
            exportConversationUseCase: mockExportConversation,
            branchConversationUseCase: mockBranchConversation,
            getChatPreferencesUseCase: mockGetChatPreferences,
            fetchMCPToolsUseCase: MockFetchMCPToolsUseCase(),
            getConversationStartersUseCase: mockGetConversationStarters,
            streamingBackgroundUseCase: background,
            notifyStreamingCompletedUseCase: notification
        )

        sutWithAgent.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))
        sutWithAgent.send(.webSearchToggled)
        sutWithAgent.send(.inputChanged("search something"))
        let completed = expectation(description: "Background task completed")
        background.onEnd = { _ in completed.fulfill() }

        // When
        sutWithAgent.send(.sendTapped)
        await fulfillment(of: [completed], timeout: 1)

        // Then
        guard case .loaded(let loadedState) = sutWithAgent.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertNotNil(loadedState.errorMessage)
        XCTAssertFalse(loadedState.isStreaming)
        XCTAssertEqual(background.completionResults, [false])
        XCTAssertEqual(notification.completionCallCount, 0)
    }
}
