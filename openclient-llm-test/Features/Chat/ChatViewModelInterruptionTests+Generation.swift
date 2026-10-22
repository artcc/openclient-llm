//
//  ChatViewModelInterruptionTests+Generation.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 21/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

extension ChatViewModelInterruptionTests {
    func test_expiration_agentWaitingForFirstToken_marksResponseAndCancelsRun() async throws {
        // Given
        makeViewModel(model: LLMModel(id: "test", capabilities: [.functionCalling]))
        agent.events = []
        agent.waitsForCancellation = true
        let started = expectation(description: "Agent started")
        agent.onExecute = { started.fulfill() }
        sut.send(.inputChanged("Question"))
        sut.send(.sendTapped)
        let task = try XCTUnwrap(sut.streamTask)
        await fulfillment(of: [started], timeout: 1)

        // When
        background.expire()
        await task.value
        _ = await sut.persistenceTask?.value

        // Then
        XCTAssertFalse(try loadedState().isStreaming)
        XCTAssertTrue(try loadedState().messages.last?.isInterruptedResponse == true)
        XCTAssertEqual(try loadedState().messages.last?.content, "")
        XCTAssertEqual(save.savedConversations.last?.messages.last?.responseInterruption, .backgroundTaskEnded)
    }

    func test_expiration_agentAfterDiscard_preservesTranscriptWithoutProvisionalText() async throws {
        // Given
        makeViewModel(model: LLMModel(id: "test", capabilities: [.functionCalling]))
        let call = ToolCall(
            id: "call", type: "function", function: .init(name: "get_current_datetime", arguments: "{}")
        )
        let transcript = [
            ChatMessage(role: .assistant, content: "", toolCalls: [call]),
            ChatMessage(role: .tool, content: "Today", toolCallId: call.id, toolName: call.function.name)
        ]
        agent.events = [.token("Provisional"), .reasoning("Provisional"), .responseDiscarded,
                        .transcriptAppended(transcript)]
        agent.waitsForCancellation = true
        let checkpoint = expectation(description: "Transcript checkpoint")
        save.executeHandler = { conversation, _ in
            checkpoint.fulfill()
            return conversation
        }
        sut.send(.inputChanged("Question"))
        sut.send(.sendTapped)
        let task = try XCTUnwrap(sut.streamTask)
        await fulfillment(of: [checkpoint], timeout: 1)
        save.executeHandler = nil

        // When
        background.expire()
        await task.value
        _ = await sut.persistenceTask?.value

        // Then
        let state = try loadedState()
        XCTAssertEqual(Array(state.messages.dropFirst().dropLast()), transcript)
        XCTAssertEqual(state.messages.last?.content, "")
        XCTAssertNil(state.messages.last?.reasoningContent)
        XCTAssertTrue(state.messages.last?.isInterruptedResponse == true)
        XCTAssertEqual(ChatMessageListState(loadedState: state).messages.count, 2)
    }

    func test_expiration_completedAgentAwaitingSave_doesNotMarkResponse() async throws {
        makeViewModel(model: LLMModel(id: "test", capabilities: [.functionCalling]))
        agent.events = [.token("Complete"), .completed]
        try await assertCompletedGenerationIsNotInterrupted()
        XCTAssertEqual(try loadedState().messages.last?.content, "Complete")
    }

    func test_expiration_completedImageAwaitingSave_doesNotMarkResponse() async throws {
        makeViewModel(model: LLMModel(id: "test", mode: .imageGeneration))
        images.result = .success(GeneratedImage(data: Data([1, 2, 3]), mimeType: "image/png", revisedPrompt: nil))
        try await assertCompletedGenerationIsNotInterrupted()
        XCTAssertEqual(try loadedState().messages.last?.attachments.count, 1)
    }

    private func assertCompletedGenerationIsNotInterrupted() async throws {
        // Given
        let gate = TestAsyncGate()
        defer { Task { await gate.open() } }
        let saving = expectation(description: "Saving completed generation")
        save.asyncExecuteHandler = { conversation, _, call in
            if call == 1 {
                saving.fulfill()
                await gate.wait()
            }
            return conversation
        }
        sut.send(.inputChanged("Question"))
        sut.send(.sendTapped)
        let task = try XCTUnwrap(sut.streamTask)
        await fulfillment(of: [saving], timeout: 1)

        // When
        background.expire()
        await gate.open()
        await task.value
        _ = await sut.persistenceTask?.value

        // Then
        XCTAssertNil(try loadedState().messages.last?.responseInterruption)
        XCTAssertEqual(notifications.expirationCallCount, 0)
    }
}
