//
//  ChatViewModelModelConfigurationTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 21/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class ChatViewModelModelConfigurationTests: XCTestCase {
    private var settings: MockSettingsManager!
    private var stream: MockStreamMessageUseCase!
    private var agent: MockAgentStreamUseCase!
    private var save: MockSaveConversationUseCase!
    private var compaction: MockCompactConversationUseCase!
    private var sut: ChatViewModel!

    override func setUp() async throws {
        try await super.setUp()
        settings = MockSettingsManager()
        stream = MockStreamMessageUseCase()
        stream.chunks = [.token("Answer")]
        agent = MockAgentStreamUseCase()
        agent.events = [.token("Agent answer")]
        save = MockSaveConversationUseCase()
        compaction = MockCompactConversationUseCase()
    }

    override func tearDown() async throws {
        sut?.send(.stopStreamingTapped)
        _ = await sut?.persistenceTask?.value
        sut = nil
        settings = nil
        stream = nil
        agent = nil
        save = nil
        compaction = nil
        try await super.tearDown()
    }

    func test_send_noConfiguration_preservesUnconfiguredParameters() async {
        sut = makeViewModel()

        await sendMessage()

        XCTAssertEqual(stream.receivedParameters, [.default])
    }

    func test_send_globalConfiguration_usesGlobalWithoutPersistingOverrides() async throws {
        settings.globalChatModelConfiguration = globalConfiguration
        sut = makeViewModel()

        await sendMessage()

        XCTAssertEqual(stream.receivedParameters, [globalConfiguration.parameters])
        let conversation = try XCTUnwrap(save.savedConversations.last)
        XCTAssertEqual(conversation.modelParameters, .default)
        XCTAssertNil(conversation.contextWindowTokens)
        XCTAssertEqual(try loadedState().contextUsage?.maxInputTokens, 8192)
    }

    func test_send_customTemperature_usesWholeChatBlockAndModelContext() async throws {
        settings.globalChatModelConfiguration = globalConfiguration
        let custom = ChatModelConfiguration(parameters: ModelParameters(temperature: 0))
        sut = makeViewModel(configuration: custom)

        await sendMessage()

        XCTAssertEqual(stream.receivedParameters, [custom.parameters])
        XCTAssertEqual(try loadedState().contextUsage?.maxInputTokens, 16384)
        XCTAssertEqual(save.savedConversations.last?.modelParameters, custom.parameters)
    }

    func test_send_customContextOnly_omitsAllGlobalGenerationParameters() async throws {
        settings.globalChatModelConfiguration = globalConfiguration
        sut = makeViewModel(configuration: ChatModelConfiguration(contextWindowTokens: 4096))

        await sendMessage()

        XCTAssertEqual(stream.receivedParameters, [.default])
        XCTAssertEqual(try loadedState().contextUsage?.maxInputTokens, 4096)
        XCTAssertEqual(save.savedConversations.last?.contextWindowTokens, 4096)
    }

    func test_send_globalMaxTokens_exceedingModelLimit_capsOnlyRequest() async {
        settings.globalChatModelConfiguration = globalConfiguration
        sut = makeViewModel(model: LLMModel(id: "test", maxInputTokens: 16384, maxOutputTokens: 1024))

        await sendMessage()

        XCTAssertEqual(stream.receivedParameters.first?.maxTokens, 1024)
        XCTAssertEqual(settings.globalChatModelConfiguration.parameters.maxTokens, 2048)
        XCTAssertEqual(save.savedConversations.last?.modelParameters, .default)
    }

    func test_configurationChanged_andReset_updatesContextAndPersistsOnlyChatBlock() async throws {
        settings.globalChatModelConfiguration = globalConfiguration
        sut = makeViewModel()
        let custom = ChatModelConfiguration(parameters: ModelParameters(topP: 0.5))

        sut.send(.modelConfigurationChanged(custom))
        _ = await sut.persistenceTask?.value
        XCTAssertEqual(try loadedState().contextUsage?.maxInputTokens, 16384)
        XCTAssertEqual(save.savedConversations.last?.modelParameters, custom.parameters)

        sut.send(.modelConfigurationChanged(.default))
        _ = await sut.persistenceTask?.value
        XCTAssertEqual(try loadedState().contextUsage?.maxInputTokens, 8192)
        XCTAssertEqual(save.savedConversations.last?.modelParameters, .default)
        XCTAssertNil(save.savedConversations.last?.contextWindowTokens)
        await sendMessage()
        XCTAssertEqual(stream.receivedParameters, [globalConfiguration.parameters])
    }

    func test_send_newChat_keepsInheritedConfigurationUnsetAfterFirstSave() async throws {
        settings.globalChatModelConfiguration = globalConfiguration
        sut = makeViewModel()
        guard case .loaded(var state) = sut.state else { return XCTFail("Expected loaded state") }
        state.conversation = nil
        sut.state = .loaded(state)

        await sendMessage()

        let conversation = try XCTUnwrap(save.savedConversations.last)
        XCTAssertEqual(conversation.modelParameters, .default)
        XCTAssertNil(conversation.contextWindowTokens)
        XCTAssertEqual(stream.receivedParameters, [globalConfiguration.parameters])
    }

    func test_send_privateChat_usesGlobalWithoutSavingConversation() async {
        settings.globalChatModelConfiguration = globalConfiguration
        sut = makeViewModel(isPrivate: true)

        await sendMessage()

        XCTAssertEqual(stream.receivedParameters, [globalConfiguration.parameters])
        XCTAssertTrue(save.savedConversations.isEmpty)
    }

    func test_regenerateAndEdit_useCurrentGlobalConfiguration() async throws {
        settings.globalChatModelConfiguration = globalConfiguration
        sut = makeViewModel()
        await sendMessage()
        let messageId = try XCTUnwrap(loadedState().messages.first?.id)
        let updated = ChatModelConfiguration(parameters: ModelParameters(maxTokens: 512))
        settings.globalChatModelConfiguration = updated

        sut.send(.regenerateLastResponse)
        await sut.streamTask?.value
        sut.send(.editMessage(id: messageId, newContent: "Edited question"))
        await sut.streamTask?.value

        XCTAssertEqual(
            stream.receivedParameters, [globalConfiguration.parameters, updated.parameters, updated.parameters]
        )
        XCTAssertEqual(save.savedConversations.last?.modelParameters, .default)
    }

    func test_regenerateAndEdit_customChat_ignoresGlobalConfiguration() async throws {
        settings.globalChatModelConfiguration = globalConfiguration
        let custom = ChatModelConfiguration(parameters: ModelParameters(temperature: 0.3))
        sut = makeViewModel(configuration: custom)
        await sendMessage()
        let messageId = try XCTUnwrap(loadedState().messages.first?.id)

        sut.send(.regenerateLastResponse)
        await sut.streamTask?.value
        sut.send(.editMessage(id: messageId, newContent: "Edited question"))
        await sut.streamTask?.value

        XCTAssertEqual(stream.receivedParameters, Array(repeating: custom.parameters, count: 3))
    }
}

extension ChatViewModelModelConfigurationTests {
    func test_globalReset_nextSendUsesServerDefaults() async {
        settings.globalChatModelConfiguration = globalConfiguration
        sut = makeViewModel()
        await sendMessage()

        settings.globalChatModelConfiguration = .default
        await sendMessage()

        XCTAssertEqual(stream.receivedParameters, [globalConfiguration.parameters, .default])
    }

    func test_reopenAndBranch_inheritedChat_usesUpdatedGlobals() async throws {
        settings.globalChatModelConfiguration = globalConfiguration
        sut = makeViewModel()
        await sendMessage()
        let saved = try XCTUnwrap(save.savedConversations.last)
        let lastMessage = try XCTUnwrap(saved.messages.last)
        let branch = BranchConversationUseCase(
            saveConversationUseCase: save, attachmentRepository: MockAttachmentRepository()
        )
        let fork = try await branch.execute(conversation: saved, fromMessageId: lastMessage.id)
        XCTAssertEqual(fork.modelParameters, .default)
        XCTAssertNil(fork.contextWindowTokens)
        settings.globalChatModelConfiguration = ChatModelConfiguration(parameters: ModelParameters(maxTokens: 512))

        sut.send(.conversationLoaded(saved))
        await sendMessage()
        sut.send(.conversationLoaded(fork))
        await sendMessage()

        XCTAssertEqual(stream.receivedParameters.suffix(2), Array(repeating: ModelParameters(maxTokens: 512), count: 2))
    }

    func test_send_customAgentConfiguration_ignoresWholeGlobalBlock() async {
        settings.globalChatModelConfiguration = globalConfiguration
        let custom = ChatModelConfiguration(parameters: ModelParameters(temperature: 0.2))
        sut = makeViewModel(
            configuration: custom,
            model: LLMModel(id: "agent", capabilities: [.functionCalling], maxInputTokens: 16384)
        )

        await sendMessage()

        XCTAssertEqual(agent.receivedParameters, [custom.parameters])
        XCTAssertEqual(agent.receivedContextWindows, [16384])
    }

    func test_globalAgentContext_compactsBeforeStartingAgent() async {
        settings.globalChatModelConfiguration = ChatModelConfiguration(
            parameters: ModelParameters(maxTokens: 512), contextWindowTokens: 3000
        )
        let history = (0..<4).flatMap { _ in
            [
                ChatMessage(role: .user, content: String(repeating: "u", count: 2500)),
                ChatMessage(role: .assistant, content: String(repeating: "a", count: 400))
            ]
        }
        compaction.result = CompactedConversation(summary: "Earlier facts", cursorMessageId: history[7].id)
        sut = makeViewModel(
            model: LLMModel(id: "agent", capabilities: [.functionCalling], maxInputTokens: 16384), history: history
        )

        await sendMessage()

        XCTAssertEqual(agent.receivedParameters, [ModelParameters(maxTokens: 512)])
        XCTAssertEqual(agent.receivedContextWindows, [3000])
        XCTAssertEqual(compaction.receivedConfigurations.first?.contextWindowTokens, 3000)
        XCTAssertEqual(save.savedConversations.last?.contextSummary, "Earlier facts")
        XCTAssertNil(save.savedConversations.last?.contextWindowTokens)
    }

    func test_send_agent_usesGlobalParametersAndContext() async {
        settings.globalChatModelConfiguration = globalConfiguration
        sut = makeViewModel(model: LLMModel(id: "agent", capabilities: [.functionCalling], maxInputTokens: 16384))

        await sendMessage()

        XCTAssertEqual(agent.receivedParameters, [globalConfiguration.parameters])
        XCTAssertEqual(agent.receivedContextWindows, [8192])
    }

    func test_globalChanged_duringAgentTurn_keepsSnapshotUntilNextTurn() async throws {
        settings.globalChatModelConfiguration = globalConfiguration
        agent.waitsForCancellation = true
        let started = expectation(description: "Agent started")
        agent.onExecute = { started.fulfill() }
        sut = makeViewModel(model: LLMModel(id: "agent", capabilities: [.functionCalling], maxInputTokens: 16384))
        sut.send(.inputChanged("First question"))
        sut.send(.sendTapped)
        await fulfillment(of: [started], timeout: 2)

        settings.globalChatModelConfiguration = ChatModelConfiguration(
            parameters: ModelParameters(maxTokens: 512), contextWindowTokens: 12000
        )
        NotificationCenter.default.post(name: .chatModelConfigurationDidChange, object: nil)
        XCTAssertEqual(agent.receivedParameters, [globalConfiguration.parameters])
        XCTAssertEqual(try loadedState().contextUsage?.maxInputTokens, 8192)
        let firstTask = sut.streamTask
        sut.send(.stopStreamingTapped)
        await firstTask?.value
        XCTAssertEqual(try loadedState().contextUsage?.maxInputTokens, 12000)
        agent.waitsForCancellation = false
        agent.onExecute = nil
        await sendMessage()

        XCTAssertEqual(agent.receivedParameters.last, settings.globalChatModelConfiguration.parameters)
        XCTAssertEqual(agent.receivedContextWindows, [8192, 12000])
    }

    func test_globalContext_compactionPersistsSummaryWithoutPersistingGlobalOverrides() async throws {
        settings.globalChatModelConfiguration = ChatModelConfiguration(
            parameters: ModelParameters(maxTokens: 512), contextWindowTokens: 1024
        )
        let history = overflowingHistory()
        compaction.result = CompactedConversation(summary: "Earlier facts", cursorMessageId: history[3].id)
        sut = makeViewModel(history: history)

        await sendMessage()

        XCTAssertEqual(stream.receivedParameters, [ModelParameters(maxTokens: 512)])
        XCTAssertEqual(compaction.receivedConfigurations.first?.contextWindowTokens, 1024)
        let saved = try XCTUnwrap(save.savedConversations.last)
        XCTAssertEqual(saved.contextSummary, "Earlier facts")
        XCTAssertNil(saved.contextWindowTokens)
        XCTAssertEqual(saved.modelParameters, .default)
    }

    func test_globalChanged_duringCompaction_keepsCapturedBlockAndCompletesRequest() async throws {
        let initial = ChatModelConfiguration(parameters: ModelParameters(maxTokens: 512), contextWindowTokens: 1024)
        settings.globalChatModelConfiguration = initial
        let history = overflowingHistory()
        compaction.result = CompactedConversation(summary: "Earlier facts", cursorMessageId: history[3].id)
        let saving = expectation(description: "Compaction persistence started")
        var resume: CheckedContinuation<Void, Never>?
        save.asyncExecuteHandler = { submitted, _, call in
            if call == 1 {
                saving.fulfill()
                await withCheckedContinuation { resume = $0 }
            }
            return submitted
        }
        sut = makeViewModel(history: history)
        sut.send(.inputChanged("Latest question"))
        sut.send(.sendTapped)
        await fulfillment(of: [saving], timeout: 2)

        settings.globalChatModelConfiguration = globalConfiguration
        resume?.resume()
        await sut.streamTask?.value

        XCTAssertEqual(stream.receivedParameters, [initial.parameters])
        XCTAssertNil(try loadedState().errorMessage)
        XCTAssertEqual(try loadedState().contextUsage?.maxInputTokens, 8192)
        XCTAssertNil(save.savedConversations.last?.contextWindowTokens)
    }

    func test_globalChanged_openIdleChat_refreshesContextWithoutSavingOverrides() async throws {
        settings.globalChatModelConfiguration = globalConfiguration
        sut = makeViewModel()
        sut.send(.modelConfigurationChanged(.default))
        _ = await sut.persistenceTask?.value
        let savedCount = save.savedConversations.count

        settings.globalChatModelConfiguration.contextWindowTokens = 12000
        NotificationCenter.default.post(name: .chatModelConfigurationDidChange, object: nil)
        for _ in 0..<1000 {
            if try loadedState().contextUsage?.maxInputTokens == 12000 { break }
            await Task.yield()
        }

        XCTAssertEqual(try loadedState().contextUsage?.maxInputTokens, 12000)
        XCTAssertEqual(try loadedState().modelConfiguration, .default)
        XCTAssertEqual(save.savedConversations.count, savedCount)
    }
}

private extension ChatViewModelModelConfigurationTests {
    var globalConfiguration: ChatModelConfiguration {
        ChatModelConfiguration(
            parameters: ModelParameters(temperature: 0.7, maxTokens: 2048, topP: 0.9), contextWindowTokens: 8192
        )
    }

    func makeViewModel(
        configuration: ChatModelConfiguration = .default,
        model: LLMModel = LLMModel(id: "test", maxInputTokens: 16384),
        history: [ChatMessage] = [],
        isPrivate: Bool = false
    ) -> ChatViewModel {
        let conversation = Conversation(
            modelId: model.id, contextWindowTokens: configuration.contextWindowTokens,
            messages: history, modelParameters: configuration.parameters
        )
        return ChatViewModel(
            isPrivateChat: isPrivate,
            state: .loaded(.init(
                conversation: isPrivate ? nil : conversation,
                messages: history, selectedModel: model, availableModels: [model],
                modelParameters: configuration.parameters, contextWindowTokens: configuration.contextWindowTokens
            )),
            streamMessageUseCase: stream,
            agentStreamUseCase: agent,
            saveConversationUseCase: save,
            fetchMCPToolsUseCase: MockFetchMCPToolsUseCase(),
            settingsManager: settings,
            getUserProfileContextUseCase: MockGetUserProfileContextUseCase(),
            getMemoryContextUseCase: MockGetMemoryContextUseCase(),
            streamingBackgroundUseCase: MockStreamingBackgroundUseCase(),
            notifyStreamingCompletedUseCase: MockNotifyStreamingCompletedUseCase(),
            compactConversationUseCase: compaction
        )
    }

    func loadedState() throws -> ChatViewModel.LoadedState {
        let loaded: ChatViewModel.LoadedState?
        if case .loaded(let state) = sut.state {
            loaded = state
        } else {
            loaded = nil
        }
        return try XCTUnwrap(loaded, "Expected loaded state")
    }

    func sendMessage() async {
        sut.send(.inputChanged("Latest question"))
        sut.send(.sendTapped)
        await sut.streamTask?.value
    }

    func overflowingHistory() -> [ChatMessage] {
        (0..<2).flatMap { index in
            [
                ChatMessage(role: .user, content: "User \(index) " + String(repeating: "u", count: 1100)),
                ChatMessage(role: .assistant, content: "Assistant \(index) " + String(repeating: "a", count: 400))
            ]
        }
    }
}
