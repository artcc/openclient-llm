//
//  ChatViewModelImageGenerationAttemptTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class ChatViewModelImageGenerationAttemptTests: XCTestCase {
    let settings = MockSettingsManager()
    let save = MockSaveConversationUseCase()
    let generation = MockGenerateImageUseCase()
    let agent = MockAgentStreamUseCase()
    let principal = LLMModel(id: "principal", capabilities: [.functionCalling])
    let generator = LLMModel(id: "generator", mode: .imageGeneration)
    let image = GeneratedImage(data: Data([1, 2, 3]), mimeType: "image/png", revisedPrompt: nil)
    private var viewModels: [ChatViewModel] = []

    override func setUp() async throws {
        try await super.setUp()
        settings.selectedModelId = principal.id
        settings.selectedImageGenerationModelId = generator.id
        generation.result = .success(image)
        agent.events = [.token("Response"), .completed]
    }

    override func tearDown() async throws {
        generation.asyncExecuteHandler = nil
        save.asyncExecuteHandler = nil
        save.executeHandler = nil
        for sut in viewModels {
            sut.errorDismissTask?.cancel()
            sut.mcpSettingsObservationTask?.cancel()
            sut.mcpDiscoveryTask?.cancel()
            sut.stopBackgroundPersistenceCheckpoints()
            sut.streamTask?.cancel()
            await sut.streamTask?.value
            _ = await sut.persistenceTask?.value
        }
        viewModels = []
        try await super.tearDown()
    }

    func test_generateImage_validAttempt_waitsForDurableUserCheckpointBeforeSpecialist() async throws {
        // Given
        let sut = makeViewModel()
        let tool = try generationTool(sut)
        let started = expectation(description: "User attempt checkpoint started")
        let checkpoint = GenerationAttemptCheckpoint()
        save.asyncExecuteHandler = { conversation, _, _ in
            XCTAssertEqual(conversation.messages.first?.imageGenerationAttempted, true)
            await withCheckedContinuation { continuation in
                checkpoint.continuation = continuation
                started.fulfill()
            }
            return conversation
        }
        let image = image
        generation.asyncExecuteHandler = { _, _, _ in
            XCTAssertTrue(checkpoint.didResume)
            return image
        }

        // When
        let task = Task { try await tool.execute(arguments: #"{"prompt":"A cat"}"#) }
        await fulfillment(of: [started], timeout: 1)
        defer { checkpoint.resume(); task.cancel() }

        // Then
        XCTAssertEqual(try loadedState(sut).messages.first?.imageGenerationAttempted, true)
        XCTAssertEqual(generation.executeCallCount, 0)
        checkpoint.resume()
        _ = try await task.value
        XCTAssertEqual(generation.executeCallCount, 1)
        XCTAssertEqual(save.savedConversations.last?.messages.first?.imageGenerationAttempted, true)
        XCTAssertFalse(try generationTool(sut).isAvailableForAdvertisement)
    }

    func test_generateImage_invalidPrompt_doesNotMarkOrPersistUser() async throws {
        // Given
        let sut = makeViewModel()
        let original = try loadedState(sut).messages
        let tool = try generationTool(sut)

        // When
        do {
            _ = try await tool.execute(arguments: #"{"prompt":" "}"#)
            XCTFail("Expected invalid prompt")
        } catch {
            XCTAssertEqual(error as? GenerateImageTool.ExecutionError, .invalidPrompt)
        }

        // Then
        XCTAssertEqual(try loadedState(sut).messages, original)
        XCTAssertTrue(save.savedConversations.isEmpty)
        XCTAssertEqual(generation.executeCallCount, 0)
        XCTAssertTrue(tool.isAvailableForAdvertisement)
    }

    func test_generateImage_requestOnlyUser_cancelsWithoutMutatingRealTurn() async throws {
        // Given
        let sut = makeViewModel()
        let original = try loadedState(sut).messages
        let tool = try generationTool(sut, messages: original + [ChatMessage(role: .user, content: "Phantom")])

        // When
        await assertCancelled(tool)

        // Then
        XCTAssertEqual(try loadedState(sut).messages, original)
        XCTAssertTrue(save.savedConversations.isEmpty)
        XCTAssertEqual(generation.executeCallCount, 0)
    }

    func test_generateImage_twoRegistriesCreatedBeforeAttempt_reservesActualUserOnlyOnce() async throws {
        // Given
        let sut = makeViewModel()
        let first = try generationTool(sut)
        let second = try generationTool(sut)

        // When
        _ = try await first.execute(arguments: #"{"prompt":"A cat"}"#)
        await assertCancelled(second)

        // Then
        XCTAssertEqual(generation.executeCallCount, 1)
        XCTAssertEqual(save.executeCallCount, 1)
        XCTAssertEqual(try loadedState(sut).messages.first?.imageGenerationAttempted, true)
    }

    func test_generateImage_userChangesDuringPersistence_cancelsBeforeSpecialist() async throws {
        // Given
        let sut = makeViewModel()
        let tool = try generationTool(sut)
        let started = expectation(description: "Checkpoint suspended")
        let checkpoint = GenerationAttemptCheckpoint()
        save.asyncExecuteHandler = { conversation, _, _ in
            await withCheckedContinuation { continuation in
                checkpoint.continuation = continuation
                started.fulfill()
            }
            return conversation
        }

        // When
        let task = Task { await self.assertCancelled(tool) }
        await fulfillment(of: [started], timeout: 1)
        defer { checkpoint.resume(); task.cancel() }
        var current = try loadedState(sut)
        current.messages.append(ChatMessage(role: .user, content: "A new turn"))
        sut.state = .loaded(current)
        checkpoint.resume()
        await task.value

        // Then
        XCTAssertEqual(generation.executeCallCount, 0)
        XCTAssertEqual(try loadedState(sut).messages.first?.imageGenerationAttempted, true)
        XCTAssertNil(try loadedState(sut).messages.last?.imageGenerationAttempted)
    }

    func test_generateImage_scopeChangesDuringPersistence_cancelsBeforeSpecialist() async throws {
        // Given
        let sut = makeViewModel()
        let tool = try generationTool(sut)
        let settings = settings
        save.executeHandler = { conversation, _ in
            settings.setServerBaseURL("https://changed.example.com")
            return conversation
        }

        // When
        await assertCancelled(tool)

        // Then
        XCTAssertEqual(generation.executeCallCount, 0)
        XCTAssertEqual(save.savedConversations.last?.messages.first?.imageGenerationAttempted, true)
    }

    func test_generateImage_persistenceFailure_keepsReservationUnderExistingCheckpointPolicy() async throws {
        // Given
        let sut = makeViewModel()
        let tool = try generationTool(sut)
        save.error = APIError.invalidResponse

        // When
        _ = try await tool.execute(arguments: #"{"prompt":"A cat"}"#)

        // Then
        XCTAssertEqual(save.executeCallCount, 1)
        XCTAssertEqual(generation.executeCallCount, 1)
        XCTAssertEqual(try loadedState(sut).messages.first?.imageGenerationAttempted, true)
        XCTAssertFalse(try generationTool(sut).isAvailableForAdvertisement)
    }

    func test_generateImage_privateChat_reservesOnlyInMemory() async throws {
        // Given
        let sut = makeViewModel(isPrivate: true)
        let tool = try generationTool(sut)

        // When
        _ = try await tool.execute(arguments: #"{"prompt":"A cat"}"#)

        // Then
        XCTAssertEqual(try loadedState(sut).messages.first?.imageGenerationAttempted, true)
        XCTAssertEqual(generation.executeCallCount, 1)
        XCTAssertTrue(save.savedConversations.isEmpty)
        XCTAssertFalse(try generationTool(sut).isAvailableForAdvertisement)
    }
}

// MARK: - Helpers

extension ChatViewModelImageGenerationAttemptTests {
    func makeViewModel(
        conversation: Conversation? = nil,
        model: LLMModel? = nil,
        isPrivate: Bool = false,
        agentUseCase: (any AgentStreamUseCaseProtocol)? = nil,
        search: (any WebSearchUseCaseProtocol)? = nil
    ) -> ChatViewModel {
        let selected = model ?? principal
        let conversation = conversation ?? Conversation(modelId: selected.id, messages: [
            ChatMessage(role: .user, content: "Draw a cat"), ChatMessage(role: .assistant, content: "Original")
        ])
        let sut = ChatViewModel(
            isPrivateChat: isPrivate,
            state: .loaded(.init(
                conversation: isPrivate ? nil : conversation, messages: conversation.messages,
                selectedModel: selected, availableModels: [selected, generator],
                modelCatalogScope: settings.getMCPAuthorizationScope(), isWebSearchEnabled: search != nil
            )),
            fetchModelsUseCase: MockFetchModelsUseCase(),
            attachmentRepository: MockAttachmentRepository(),
            streamMessageUseCase: MockStreamMessageUseCase(),
            generateImageUseCase: MockGenerateImageUseCase(),
            agentStreamUseCase: agentUseCase ?? agent,
            webSearchUseCase: search ?? MockWebSearchUseCase(),
            saveConversationUseCase: save,
            getChatPreferencesUseCase: MockGetChatPreferencesUseCase(),
            saveSelectedModelUseCase: MockSaveSelectedModelUseCase(),
            fetchMCPToolsUseCase: MockFetchMCPToolsUseCase(),
            settingsManager: settings,
            getUserProfileContextUseCase: MockGetUserProfileContextUseCase(),
            getMemoryContextUseCase: MockGetMemoryContextUseCase(),
            memoryManager: MockMemoryManager(),
            triggerHapticFeedbackUseCase: MockTriggerHapticFeedbackUseCase(),
            streamingBackgroundUseCase: MockStreamingBackgroundUseCase(),
            notifyStreamingCompletedUseCase: MockNotifyStreamingCompletedUseCase(),
            compactConversationUseCase: MockCompactConversationUseCase(),
            imageToolGenerationUseCase: generation
        )
        viewModels.append(sut)
        return sut
    }

    func loadedState(_ sut: ChatViewModel) throws -> ChatViewModel.LoadedState {
        guard case .loaded(let state) = sut.state else { throw CancellationError() }
        return state
    }

    func generationTool(_ sut: ChatViewModel, messages: [ChatMessage]? = nil) throws -> GenerateImageTool {
        var tools: [any ChatToolProtocol] = []
        sut.appendImageTools(from: try loadedState(sut), messages: messages, to: &tools)
        return try XCTUnwrap(tools.compactMap { $0 as? GenerateImageTool }.first)
    }

    func assertCancelled(_ tool: GenerateImageTool, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await tool.execute(arguments: #"{"prompt":"A cat"}"#)
            XCTFail("Expected cancellation", file: file, line: line)
        } catch {
            XCTAssertTrue(error is CancellationError, file: file, line: line)
        }
    }

    func regenerate(_ sut: ChatViewModel) async throws {
        sut.send(.regenerateLastResponse)
        let task = try XCTUnwrap(sut.streamTask)
        await task.value
    }
}

@MainActor
private final class GenerationAttemptCheckpoint {
    var continuation: CheckedContinuation<Void, Never>?
    var didResume = false

    func resume() {
        didResume = true
        continuation?.resume()
        continuation = nil
    }
}
