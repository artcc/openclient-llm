//
//  ChatViewModelInterruptionTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 21/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class ChatViewModelInterruptionTests: XCTestCase {
    let stream = ControlledInterruptionStream()
    let background = MockStreamingBackgroundUseCase()
    let save = MockSaveConversationUseCase()
    let notifications = MockNotifyStreamingCompletedUseCase()
    let settings = MockSettingsManager()
    let agent = MockAgentStreamUseCase()
    let images = MockGenerateImageUseCase()
    var sut: ChatViewModel!

    override func tearDown() async throws {
        let task = sut?.streamTask
        sut?.send(.viewDisappeared)
        stream.continuations.forEach { $0.finish() }
        await task?.value
        _ = await sut?.persistenceTask?.value
        sut?.errorDismissTask?.cancel()
        sut?.mcpSettingsObservationTask?.cancel()
        sut?.modelConfigurationObservationTask?.cancel()
        sut?.builtInToolSettingsObservationTask?.cancel()
        sut = nil
        try await super.tearDown()
    }

    func test_expiration_beforeFirstToken_persistsVisibleInterruptedResponse() async throws {
        // Given
        makeViewModel()
        let task = try await startResponse()
        let id = try XCTUnwrap(sut.activeAssistantMessageId)
        let expiration = background.expirationHandler

        // When
        background.expire()
        expiration?()
        await task.value
        _ = await sut.persistenceTask?.value

        // Then
        let state = try loadedState()
        XCTAssertFalse(state.isStreaming)
        XCTAssertNil(sut.activeAssistantMessageId)
        XCTAssertNil(sut.backgroundPersistenceObserver)
        XCTAssertNil(sut.backgroundPersistenceCheckpointTask)
        XCTAssertEqual(state.messages.last?.id, id)
        XCTAssertEqual(state.messages.last?.content, "")
        XCTAssertEqual(state.messages.last?.responseInterruption, .backgroundTaskEnded)
        XCTAssertEqual(ChatMessageListState(loadedState: state).messages.last?.id, id)
        XCTAssertEqual(save.savedConversations.last?.messages, state.messages)
        XCTAssertEqual(notifications.expirationCallCount, 1)
        let restored = try JSONDecoder().decode(Conversation.self, from: JSONEncoder().encode(
            XCTUnwrap(save.savedConversations.last)
        ))
        sut.send(.conversationLoaded(restored))
        XCTAssertTrue(try loadedState().messages.last?.isInterruptedResponse == true)
    }

    func test_expiration_bufferedContent_preservesTextReasoningImageAndUsage() async throws {
        // Given
        makeViewModel()
        let task = try await startResponse()
        let id = try XCTUnwrap(sut.activeAssistantMessageId)
        sut.enqueueStreamingTextUpdate(.token("Partial"), assistantMessageId: id)
        sut.enqueueStreamingTextUpdate(.token(" answer"), assistantMessageId: id)
        sut.enqueueStreamingTextUpdate(.reasoning("Reasoning"), assistantMessageId: id)
        var state = try loadedState()
        let attachment = ChatMessage.Attachment(
            type: .image, fileName: "image.png", mimeType: "image/png",
            fileRelativePath: "", transientData: Data([1, 2, 3])
        )
        state.messages[state.messages.count - 1].attachments = [attachment]
        state.messages[state.messages.count - 1].tokenUsage = TokenUsage(totalTokens: 12)
        sut.state = .loaded(state)

        // When
        background.expire()
        await task.value
        _ = await sut.persistenceTask?.value

        // Then
        let response = try XCTUnwrap(loadedState().messages.last)
        XCTAssertEqual(response.content, "Partial answer")
        XCTAssertEqual(response.reasoningContent, "Reasoning")
        XCTAssertEqual(response.attachments, [attachment])
        XCTAssertEqual(response.tokenUsage?.totalTokens, 12)
        XCTAssertTrue(response.isInterruptedResponse)
        XCTAssertTrue(sut.streamingUpdateBuffer.updates.isEmpty)
        XCTAssertEqual(save.savedConversations.last?.messages.last, response)
    }

    func test_expiration_privateChat_keepsStatusOnlyInMemory() async throws {
        // Given
        makeViewModel(isPrivate: true)
        let task = try await startResponse()

        // When
        background.expire()
        await task.value
        _ = await sut.persistenceTask?.value

        // Then
        XCTAssertTrue(try loadedState().messages.last?.isInterruptedResponse == true)
        XCTAssertNil(try loadedState().conversation)
        XCTAssertTrue(save.savedConversations.isEmpty)
    }

    func test_stopStreaming_manualStop_doesNotMarkBackgroundInterruption() async throws {
        // Given
        makeViewModel()
        let task = try await startResponse()

        // When
        sut.send(.stopStreamingTapped)
        background.expire()
        await task.value

        // Then
        XCTAssertNil(try loadedState().messages.last?.responseInterruption)
        XCTAssertEqual(notifications.expirationCallCount, 0)
    }

    func test_expiration_lateCallback_doesNotAffectReplacementResponse() async throws {
        // Given
        makeViewModel()
        let oldTask = try await startResponse()
        let oldExpiration = background.expirationHandler
        sut.send(.stopStreamingTapped)
        await oldTask.value
        let newTask = try await startResponse()
        let newId = sut.activeAssistantMessageId

        // When
        oldExpiration?()

        // Then
        XCTAssertTrue(try loadedState().isStreaming)
        XCTAssertEqual(sut.activeAssistantMessageId, newId)
        XCTAssertNil(try loadedState().messages.last?.responseInterruption)
        XCTAssertEqual(notifications.expirationCallCount, 0)
        sut.send(.stopStreamingTapped)
        await newTask.value
    }

    func makeViewModel(isPrivate: Bool = false, conversation: Conversation? = nil, model: LLMModel? = nil) {
        let model = model ?? LLMModel(id: "test")
        sut = ChatViewModel(
            isPrivateChat: isPrivate,
            state: .loaded(.init(
                conversation: conversation, messages: conversation?.messages ?? [],
                selectedModel: model, availableModels: [model], modelCatalogScope: settings.getMCPAuthorizationScope()
            )),
            fetchModelsUseCase: MockFetchModelsUseCase(),
            prepareImageAttachmentUseCase: MockPrepareImageAttachmentUseCase(),
            attachmentRepository: MockAttachmentRepository(),
            streamMessageUseCase: stream,
            generateImageUseCase: images,
            agentStreamUseCase: agent,
            webSearchUseCase: MockWebSearchUseCase(),
            saveConversationUseCase: save,
            getChatPreferencesUseCase: MockGetChatPreferencesUseCase(),
            saveSelectedModelUseCase: MockSaveSelectedModelUseCase(),
            fetchMCPToolsUseCase: MockFetchMCPToolsUseCase(),
            settingsManager: settings,
            getUserProfileContextUseCase: MockGetUserProfileContextUseCase(),
            getMemoryContextUseCase: MockGetMemoryContextUseCase(),
            memoryManager: MockMemoryManager(),
            recordAudioUseCase: MockRecordAudioUseCase(),
            streamingBackgroundUseCase: background,
            notifyStreamingCompletedUseCase: notifications,
            compactConversationUseCase: MockCompactConversationUseCase()
        )
    }

    func startResponse() async throws -> Task<Void, Never> {
        let started = expectation(description: "Stream started")
        stream.onExecute = { started.fulfill() }
        sut.send(.inputChanged("Question"))
        sut.send(.sendTapped)
        let task = try XCTUnwrap(sut.streamTask)
        await fulfillment(of: [started], timeout: 1)
        stream.onExecute = nil
        return task
    }

    func loadedState() throws -> ChatViewModel.LoadedState {
        guard case .loaded(let state) = sut.state else { throw APIError.invalidResponse }
        return state
    }

    func interruptedConversation() -> Conversation {
        Conversation(modelId: "test", messages: [
            ChatMessage(role: .user, content: "Question"),
            ChatMessage(role: .assistant, content: "", responseInterruption: .backgroundTaskEnded)
        ])
    }
}

@MainActor
final class ControlledInterruptionStream: StreamMessageUseCaseProtocol {
    var continuations: [AsyncThrowingStream<StreamChunk, Error>.Continuation] = []
    var receivedMessages: [[ChatMessage]] = []
    var receivedParameters: [ModelParameters] = []
    var onExecute: (() -> Void)?

    func execute(
        messages: [ChatMessage], model: String, parameters: ModelParameters
    ) -> AsyncThrowingStream<StreamChunk, Error> {
        receivedMessages.append(messages)
        receivedParameters.append(parameters)
        let stream = AsyncThrowingStream<StreamChunk, Error> { continuations.append($0) }
        onExecute?()
        return stream
    }
}
