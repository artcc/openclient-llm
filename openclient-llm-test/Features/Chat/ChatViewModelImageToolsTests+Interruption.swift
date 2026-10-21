//
//  ChatViewModelImageToolsTests+Interruption.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 21/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

extension ChatViewModelImageToolsTests {
    func test_retry_interruptedImageEdit_keepsImageTranscriptAndConsumedReservation() async throws {
        // Given
        let call = ToolCall(id: "edit", type: "function", function: .init(name: "edit_image", arguments: "{}"))
        let image = imageAttachment()
        let response = ChatMessage(
            role: .assistant, content: "Partial", attachments: [image], responseInterruption: .backgroundTaskEnded
        )
        let conversation = Conversation(modelId: principal.id, messages: [
            ChatMessage(
                role: .user, content: "Edit", imageGenerationAttempted: true, imageOperationAttempted: .editing
            ),
            ChatMessage(role: .assistant, content: "", toolCalls: [call]),
            ChatMessage(role: .tool, content: "Edited image", toolCallId: call.id, toolName: call.function.name),
            response
        ])
        let sut = makeViewModel(conversation: conversation)

        // When
        sut.send(.retryInterruptedResponse(response.id))
        let task = try XCTUnwrap(sut.streamTask)
        await task.value

        // Then
        let state = try loadedState(sut)
        XCTAssertEqual(Array(state.messages.dropLast()), Array(conversation.messages.dropLast()))
        XCTAssertEqual(state.messages.last?.attachments, [image])
        XCTAssertNil(state.messages.last?.responseInterruption)
        XCTAssertFalse(agent.receivedToolNames.contains("generate_image"))
        XCTAssertFalse(agent.receivedToolNames.contains("edit_image"))
        XCTAssertEqual(specialistGeneration.executeCallCount, 0)
        XCTAssertEqual(nativeGeneration.executeCallCount, 0)
    }

    func test_retry_interruptedEditAfterNativeModelSwitch_rejectsWithoutAlteringHistory() throws {
        // Given
        let model = LLMModel(id: "native", capabilities: [.imageGeneration])
        let response = ChatMessage(role: .assistant, content: "", responseInterruption: .backgroundTaskEnded)
        let conversation = Conversation(modelId: principal.id, messages: [
            ChatMessage(
                role: .user, content: "Edit", imageGenerationAttempted: true, imageOperationAttempted: .editing
            ),
            response
        ])
        let sut = makeViewModel(model: model, conversation: conversation)

        // When
        sut.send(.retryInterruptedResponse(response.id))

        // Then
        XCTAssertEqual(try loadedState(sut).messages, conversation.messages)
        XCTAssertNotNil(try loadedState(sut).errorMessage)
        XCTAssertNil(sut.streamTask)
        XCTAssertEqual(nativeGeneration.executeCallCount, 0)
        XCTAssertEqual(specialistGeneration.executeCallCount, 0)
    }
}
