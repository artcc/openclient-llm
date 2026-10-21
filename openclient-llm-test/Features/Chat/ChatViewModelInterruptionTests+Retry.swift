//
//  ChatViewModelInterruptionTests+Retry.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 21/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

extension ChatViewModelInterruptionTests {
    func test_retry_repeatedTap_reusesUserAttachmentsAndCurrentGlobalConfigurationOnce() async throws {
        // Given
        var conversation = interruptedConversation()
        conversation.messages[0].attachments = [.init(
            type: .image, fileName: "input.png", mimeType: "image/png",
            fileRelativePath: "", transientData: Data([1, 2, 3])
        )]
        makeViewModel(conversation: conversation, model: LLMModel(id: "test", capabilities: [.vision]))
        settings.globalChatModelConfiguration = ChatModelConfiguration(parameters: ModelParameters(temperature: 0.4))
        let response = try XCTUnwrap(conversation.messages.last)
        let started = expectation(description: "Retry starts once")
        stream.onExecute = { started.fulfill() }
        sut.send(.inputChanged("Unsent draft"))

        // When
        sut.send(.retryInterruptedResponse(response.id))
        let task = try XCTUnwrap(sut.streamTask)
        sut.send(.retryInterruptedResponse(response.id))
        await fulfillment(of: [started], timeout: 1)

        // Then
        let state = try loadedState()
        XCTAssertEqual(stream.receivedMessages.count, 1)
        XCTAssertEqual(stream.receivedMessages[0].filter { $0.role == .user }, [conversation.messages[0]])
        XCTAssertEqual(stream.receivedParameters.first?.temperature, 0.4)
        XCTAssertEqual(state.messages.filter { $0.role == .user }.count, 1)
        XCTAssertEqual(state.inputText, "Unsent draft")
        XCTAssertNil(state.messages.last?.responseInterruption)
        XCTAssertNotEqual(state.messages.last?.id, response.id)
        sut.send(.stopStreamingTapped)
        await task.value
    }

    func test_retry_secondExpiration_usesNewAttemptIdentity() async throws {
        // Given
        let conversation = interruptedConversation()
        makeViewModel(conversation: conversation)
        let oldId = try XCTUnwrap(conversation.messages.last?.id)
        let started = expectation(description: "Retry started")
        stream.onExecute = { started.fulfill() }
        sut.send(.retryInterruptedResponse(oldId))
        let task = try XCTUnwrap(sut.streamTask)
        await fulfillment(of: [started], timeout: 1)
        let newId = try XCTUnwrap(sut.activeAssistantMessageId)

        // When
        background.expire()
        await task.value
        _ = await sut.persistenceTask?.value

        // Then
        XCTAssertNotEqual(newId, oldId)
        XCTAssertEqual(try loadedState().messages.last?.id, newId)
        XCTAssertTrue(try loadedState().messages.last?.isInterruptedResponse == true)
        XCTAssertEqual(try loadedState().messages.count, 2)
    }

    func test_retry_staleOrUnmarkedMessage_doesNotStartRequest() throws {
        // Given
        let conversation = interruptedConversation()
        makeViewModel(conversation: conversation)

        // When
        sut.send(.retryInterruptedResponse(UUID()))
        var state = try loadedState()
        state.messages[state.messages.count - 1].responseInterruption = nil
        sut.state = .loaded(state)
        sut.send(.retryInterruptedResponse(try XCTUnwrap(state.messages.last?.id)))

        // Then
        XCTAssertNil(sut.streamTask)
        XCTAssertEqual(try loadedState().messages, state.messages)
        XCTAssertTrue(stream.receivedMessages.isEmpty)
    }

    func test_retry_busyComposerOrHandoff_doesNotChangeHistory() throws {
        // Given
        let conversation = interruptedConversation()
        makeViewModel(conversation: conversation)
        let id = try XCTUnwrap(conversation.messages.last?.id)
        let initial = try loadedState()
        let busyFlags: [WritableKeyPath<ChatViewModel.LoadedState, Bool>] = [
            \.isStreaming, \.isPreparingAttachment, \.isStartingRecording, \.isRecording, \.isTranscribing
        ]
        for flag in busyFlags {
            var busy = initial
            busy[keyPath: flag] = true
            sut.state = .loaded(busy)

            // When
            sut.send(.retryInterruptedResponse(id))

            // Then
            XCTAssertFalse(ChatMessageListState(loadedState: busy).canRetryInterruptedResponse)
            XCTAssertEqual(try loadedState().messages, initial.messages)
            XCTAssertNil(sut.streamTask)
        }
        sut.state = .loaded(initial)
        sut.isPreparingAppHandoff = true
        sut.send(.retryInterruptedResponse(id))
        sut.isPreparingAppHandoff = false
        XCTAssertNil(sut.streamTask)
        XCTAssertTrue(stream.receivedMessages.isEmpty)
    }

    func test_retry_customChatConfiguration_preservesOverridesAndCompletedResult() async throws {
        // Given
        var conversation = interruptedConversation()
        conversation.modelParameters = ModelParameters(temperature: 0.7)
        settings.globalChatModelConfiguration = ChatModelConfiguration(parameters: ModelParameters(temperature: 0.1))
        makeViewModel(conversation: conversation)
        var state = try loadedState()
        state.modelParameters = conversation.modelParameters
        sut.state = .loaded(state)
        let started = expectation(description: "Retry started")
        stream.onExecute = { started.fulfill() }

        // When
        sut.send(.retryInterruptedResponse(try XCTUnwrap(conversation.messages.last?.id)))
        let task = try XCTUnwrap(sut.streamTask)
        await fulfillment(of: [started], timeout: 1)
        stream.continuations.last?.yield(.token("Recovered"))
        stream.continuations.last?.finish()
        await task.value

        // Then
        XCTAssertEqual(stream.receivedParameters.first?.temperature, 0.7)
        XCTAssertEqual(try loadedState().messages.last?.content, "Recovered")
        XCTAssertNil(try loadedState().messages.last?.responseInterruption)
        XCTAssertNil(save.savedConversations.last?.messages.last?.responseInterruption)
        XCTAssertEqual(notifications.completionCallCount, 1)
    }
}
