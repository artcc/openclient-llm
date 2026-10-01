//
//  ChatViewModelAgentStreamingTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 01/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class ChatViewModelAgentStreamingTests: XCTestCase {
    private let agent = MockAgentStreamUseCase()
    private let background = MockStreamingBackgroundUseCase()
    private let save = MockSaveConversationUseCase()
    private var viewModels: [ChatViewModel] = []

    override func tearDown() async throws {
        for viewModel in viewModels {
            let task = viewModel.streamTask
            viewModel.send(.viewDisappeared)
            viewModel.errorDismissTask?.cancel()
            viewModel.mcpSettingsObservationTask?.cancel()
            viewModel.mcpDiscoveryTask?.cancel()
            await task?.value
            _ = await viewModel.persistenceTask?.value
        }
        viewModels = []
        try await super.tearDown()
    }

    func test_send_discardedRound_doesNotLeakBufferedProgressIntoFinalResponse() async throws {
        // Given
        agent.events = [
            .token("Intermediate"), .token(" text"), .reasoning("Intermediate reasoning"),
            .responseDiscarded,
            .reasoning("Final reasoning"), .token("Final"), .token(" answer"), .completed
        ]
        let sut = makeViewModel()

        // When
        let state = try await send(sut)

        // Then
        XCTAssertEqual(state.messages.last?.content, "Final answer")
        XCTAssertEqual(state.messages.last?.reasoningContent, "Final reasoning")
        XCTAssertFalse(state.isStreaming)
        XCTAssertNil(state.errorMessage)
        XCTAssertTrue(sut.streamingUpdateBuffer.updates.isEmpty)
        XCTAssertNil(sut.streamingUpdateBuffer.flushTask)
        XCTAssertEqual(background.completionResults, [true])
    }

    func test_send_errorWithBufferedProgress_preservesPartialContentAndReasoning() async throws {
        // Given
        agent.events = [.token("Partial"), .token(" tail"), .reasoning("Reasoning")]
        agent.error = APIError.serverUnreachable
        let sut = makeViewModel()

        // When
        let state = try await send(sut)

        // Then
        XCTAssertEqual(state.messages.last?.content, "Partial tail")
        XCTAssertEqual(state.messages.last?.reasoningContent, "Reasoning")
        XCTAssertFalse(state.isStreaming)
        XCTAssertNotNil(state.errorMessage)
        XCTAssertNil(sut.streamingUpdateBuffer.flushTask)
        XCTAssertEqual(background.completionResults, [false])
    }

    func test_send_discardedProgress_preservesDeliveredImagesAndUsage() async throws {
        // Given
        let data = try XCTUnwrap(Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"))
        agent.events = [
            .generatedImage(GeneratedImage(data: data, mimeType: "image/gif", revisedPrompt: nil)),
            .usage(TokenUsage(promptTokens: 10, completionTokens: 5, totalTokens: 15)),
            .token("Intermediate"), .token(" text"), .responseDiscarded,
            .token("Answer"), .completed
        ]
        let sut = makeViewModel()

        // When
        let state = try await send(sut)

        // Then
        XCTAssertEqual(state.messages.last?.content, "Answer")
        XCTAssertEqual(state.messages.last?.attachments.first?.transientData, data)
        XCTAssertEqual(state.messages.last?.attachments.count, 1)
        XCTAssertEqual(state.messages.last?.tokenUsage?.totalTokens, 15)
        XCTAssertNil(state.errorMessage)
    }

    func test_send_tokenBurst_groupsUpdatesAndFlushesCompleteAnswer() async throws {
        // Given
        agent.events = (0..<1_000).map { _ in .token("a") } + [.completed]
        let sut = makeViewModel()

        // When
        let state = try await send(sut)

        // Then
        XCTAssertEqual(state.messages.last?.content, String(repeating: "a", count: 1_000))
        XCTAssertLessThan(state.streamingRevision, 1_000)
        XCTAssertNil(sut.activeAssistantMessageId)
        XCTAssertNil(state.errorMessage)
    }

    func test_send_invalidToolRound_doesNotPersistOrRestoreProvisionalResponse() async throws {
        // Given
        let api = MockAPIClient()
        api.streamChunks = try [
            AgentStreamingFixture.chunk(content: "Provisional answer", reasoning: "Provisional reasoning"),
            AgentStreamingFixture.chunk(calls: [
                AgentStreamingFixture.call(id: "call", name: "get_current_datetime", arguments: "{")
            ], finish: "length")
        ]
        let useCase = AgentStreamUseCase(
            repository: ChatRepository(apiClient: api, attachmentRepository: MockAttachmentRepository()),
            chunkDelay: .zero
        )
        let sut = makeViewModel(isPrivateChat: false, agentStreamUseCase: useCase)

        // When
        let state = try await send(sut)
        let saved = try XCTUnwrap(save.savedConversations.last)
        let restoredConversation = try JSONDecoder().decode(Conversation.self, from: JSONEncoder().encode(saved))
        let restored = makeViewModel(isPrivateChat: false)
        restored.send(.conversationLoaded(restoredConversation))

        // Then
        XCTAssertNotNil(state.errorMessage)
        XCTAssertFalse(state.isStreaming)
        XCTAssertEqual(saved.messages.map(\.role), [.user])
        XCTAssertEqual(saved.messages, state.messages)
        guard case .loaded(let restoredState) = restored.state else { return XCTFail("Expected restored conversation") }
        XCTAssertEqual(restoredState.messages, saved.messages)
        XCTAssertTrue(sut.streamingUpdateBuffer.updates.isEmpty)
        XCTAssertNil(sut.streamingUpdateBuffer.flushTask)
        XCTAssertEqual(api.streamRequestCount, 1)
    }

    // MARK: - Private

    private func send(_ sut: ChatViewModel) async throws -> ChatViewModel.LoadedState {
        sut.send(.inputChanged("Question"))
        sut.send(.sendTapped)
        let task = try XCTUnwrap(sut.streamTask)
        await task.value
        guard case .loaded(let state) = sut.state else { throw APIError.invalidResponse }
        return state
    }

    private func makeViewModel(
        isPrivateChat: Bool = true,
        agentStreamUseCase: (any AgentStreamUseCaseProtocol)? = nil
    ) -> ChatViewModel {
        let model = LLMModel(id: "test", capabilities: [.functionCalling])
        let settings = MockSettingsManager()
        let sut = ChatViewModel(
            isPrivateChat: isPrivateChat,
            state: .loaded(.init(selectedModel: model, availableModels: [model])),
            fetchModelsUseCase: MockFetchModelsUseCase(),
            attachmentRepository: MockAttachmentRepository(),
            streamMessageUseCase: MockStreamMessageUseCase(),
            agentStreamUseCase: agentStreamUseCase ?? agent,
            webSearchUseCase: MockWebSearchUseCase(),
            saveConversationUseCase: save,
            getChatPreferencesUseCase: MockGetChatPreferencesUseCase(),
            saveSelectedModelUseCase: MockSaveSelectedModelUseCase(),
            fetchMCPToolsUseCase: MockFetchMCPToolsUseCase(),
            settingsManager: settings,
            getUserProfileContextUseCase: MockGetUserProfileContextUseCase(),
            getMemoryContextUseCase: MockGetMemoryContextUseCase(),
            memoryManager: MockMemoryManager(),
            triggerHapticFeedbackUseCase: MockTriggerHapticFeedbackUseCase(),
            streamingBackgroundUseCase: background,
            notifyStreamingCompletedUseCase: MockNotifyStreamingCompletedUseCase(),
            compactConversationUseCase: MockCompactConversationUseCase()
        )
        viewModels.append(sut)
        return sut
    }
}
