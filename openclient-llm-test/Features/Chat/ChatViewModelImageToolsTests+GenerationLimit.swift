//
//  ChatViewModelImageToolsTests+GenerationLimit.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
extension ChatViewModelImageToolsTests {
    func test_agentToolDefinitions_restoredGenerationResult_hidesGenerationRegardlessOfSuccess() throws {
        // Given
        for succeeded in [true, false] {
            let conversation = try restoredGenerationConversation(succeeded: succeeded)
            let sut = makeViewModel(conversation: conversation)

            // When
            let definitions = sut.agentToolDefinitions(for: try loadedState(sut))

            // Then
            XCTAssertFalse(definitions.contains { $0.function.name == "generate_image" })
            XCTAssertTrue(definitions.contains { $0.function.name == "get_current_datetime" })
            XCTAssertEqual(try loadedState(sut).messages, conversation.messages)
            try assertPrincipalUnchanged(sut)
        }
        XCTAssertEqual(specialistGeneration.executeCallCount, 0)
    }

    func test_regenerateLastResponse_restoredSuccessfulGeneration_retainsImageAndRejectsSecondAttempt() async throws {
        // Given
        let conversation = try restoredGenerationConversation(succeeded: true)
        let original = try XCTUnwrap(conversation.messages.last)
        XCTAssertEqual(original.attachments.count, 1)
        let sut = makeViewModel(conversation: conversation)

        // When
        sut.send(.regenerateLastResponse)
        let task = try XCTUnwrap(sut.streamTask)
        XCTAssertEqual(try loadedState(sut).messages.last?.attachments, original.attachments)
        await task.value
        let registry = try capturedRegistry()
        try await assertGenerationLimit(registry)

        // Then
        let state = try loadedState(sut)
        XCTAssertEqual(state.messages.last?.attachments, original.attachments)
        XCTAssertEqual(state.messages.last?.content, "Response")
        XCTAssertEqual(Array(state.messages.dropLast()), Array(conversation.messages.dropLast()))
        XCTAssertFalse(agent.receivedToolNames.contains("generate_image"))
        XCTAssertEqual(try XCTUnwrap(agent.receivedToolContext).additionalExecutionTime, .zero)
        XCTAssertEqual(specialistGeneration.executeCallCount, 0)
        XCTAssertEqual(nativeGeneration.executeCallCount, 0)
        XCTAssertNil(apiClient.lastRequestBody)
        try assertPrincipalUnchanged(sut)
    }

    func test_regenerateLastResponse_restoredFailedGeneration_rejectsRetryWithoutExtraTime() async throws {
        // Given
        let conversation = try restoredGenerationConversation(succeeded: false)
        let sut = makeViewModel(conversation: conversation)

        // When
        let registry = try await regenerationRegistry(sut)
        try await assertGenerationLimit(registry)

        // Then
        let state = try loadedState(sut)
        XCTAssertEqual(state.messages.last?.attachments, [])
        XCTAssertEqual(state.messages.last?.content, "Response")
        XCTAssertEqual(Array(state.messages.dropLast()), Array(conversation.messages.dropLast()))
        XCTAssertFalse(agent.receivedToolNames.contains("generate_image"))
        XCTAssertEqual(try XCTUnwrap(agent.receivedToolContext).additionalExecutionTime, .zero)
        XCTAssertEqual(specialistGeneration.executeCallCount, 0)
        XCTAssertEqual(nativeGeneration.executeCallCount, 0)
        XCTAssertNil(apiClient.lastRequestBody)
        try assertPrincipalUnchanged(sut)
    }

    func test_send_newUserAfterConsumedTurn_createsRegistryAllowingOneGeneration() async throws {
        // Given
        for succeeded in [true, false] {
            let conversation = try restoredGenerationConversation(succeeded: succeeded)
            let sut = makeViewModel(conversation: conversation)
            let consumedRegistry = try await regenerationRegistry(sut)
            try await assertGenerationLimit(consumedRegistry)
            let previousMessages = try loadedState(sut).messages

            // When
            try await sendMessage(sut, prompt: "Draw a different mountain")
            let registry = try capturedRegistry()
            try await assertOneGeneration(registry)

            // Then
            XCTAssertTrue(agent.receivedToolNames.contains("generate_image"))
            XCTAssertEqual(try XCTUnwrap(agent.receivedToolContext).additionalExecutionTime, .seconds(600))
            XCTAssertEqual(Array(try loadedState(sut).messages.prefix(previousMessages.count)), previousMessages)
            try await assertGenerationLimit(consumedRegistry)
            try assertPrincipalUnchanged(sut)
        }
        XCTAssertEqual(specialistGeneration.executeCallCount, 2)
        XCTAssertEqual(specialistGeneration.models, [generator.id, generator.id])
        XCTAssertEqual(nativeGeneration.executeCallCount, 0)
    }

    func test_regenerateLastResponse_reselectedSpecialistInConsumedTurn_stillRejectsGeneration() async throws {
        // Given
        let otherGenerator = LLMModel(id: "other-generator", mode: .imageGeneration)
        for succeeded in [true, false] {
            settings.setSelectedImageGenerationModelId(generator.id)
            let conversation = try restoredGenerationConversation(succeeded: succeeded)
            let sut = makeViewModel(conversation: conversation, extraModels: [otherGenerator])
            let firstRegistry = try await regenerationRegistry(sut)
            try await assertGenerationLimit(firstRegistry)

            // When
            settings.setSelectedImageGenerationModelId(otherGenerator.id)
            let registry = try await regenerationRegistry(sut)
            try await assertGenerationLimit(registry)

            // Then
            XCTAssertFalse(try visualToolNames(sut).contains("generate_image"))
            XCTAssertEqual(try loadedState(sut).messages.last?.attachments, conversation.messages.last?.attachments)
            XCTAssertEqual(try XCTUnwrap(agent.receivedToolContext).additionalExecutionTime, .zero)
            XCTAssertEqual(settings.getSelectedImageGenerationModelId(), otherGenerator.id)
            try assertPrincipalUnchanged(sut)
        }
        XCTAssertEqual(specialistGeneration.executeCallCount, 0)
        XCTAssertTrue(specialistGeneration.models.isEmpty)
        XCTAssertEqual(nativeGeneration.executeCallCount, 0)
        XCTAssertNil(apiClient.lastRequestBody)
    }

    func test_regenerateLastResponse_generationOnlyInOlderTurn_allowsOneGeneration() async throws {
        // Given
        var conversation = try restoredGenerationConversation(succeeded: true)
        let olderTurn = conversation.messages
        conversation.messages += [
            ChatMessage(role: .user, content: "Draw a lake"),
            ChatMessage(role: .assistant, content: "Original response")
        ]
        let sut = makeViewModel(conversation: conversation)

        // When
        let names = try visualToolNames(sut)
        let registry = try await regenerationRegistry(sut)
        try await assertOneGeneration(registry)

        // Then
        XCTAssertTrue(names.contains("generate_image"))
        XCTAssertTrue(agent.receivedToolNames.contains("generate_image"))
        XCTAssertEqual(Array(try loadedState(sut).messages.prefix(olderTurn.count)), olderTurn)
        XCTAssertEqual(try loadedState(sut).messages.last?.attachments, [])
        XCTAssertEqual(specialistGeneration.executeCallCount, 1)
        XCTAssertEqual(specialistGeneration.models, [generator.id])
        XCTAssertEqual(nativeGeneration.executeCallCount, 0)
        try assertPrincipalUnchanged(sut)
    }

    func test_appendImageTools_newUserOverridesConsumedHistory_estimatesGenerationDefinition() throws {
        // Given
        let conversation = try restoredGenerationConversation(succeeded: false)
        let sut = makeViewModel(conversation: conversation)
        let messages = conversation.messages + [ChatMessage(role: .user, content: "Draw a lake")]
        XCTAssertFalse(try visualToolNames(sut).contains("generate_image"))

        // When
        var tools: [any ChatToolProtocol] = []
        sut.appendImageTools(from: try loadedState(sut), messages: messages, to: &tools)
        let registry = ToolRegistry(tools: tools)

        // Then
        XCTAssertTrue(registry.definitions.contains { $0.function.name == "generate_image" })
        XCTAssertEqual(try loadedState(sut).messages, conversation.messages)
        XCTAssertEqual(specialistGeneration.executeCallCount, 0)
        XCTAssertTrue(specialistGeneration.models.isEmpty)
        try assertPrincipalUnchanged(sut)
    }
}

// MARK: - Helpers

private extension ChatViewModelImageToolsTests {
    func restoredGenerationConversation(succeeded: Bool) throws -> Conversation {
        let conversationId = UUID()
        let image = imageAttachment(conversationId: conversationId, data: nil)
        let call = ToolCall(
            id: "call-image", type: "function",
            function: .init(name: "generate_image", arguments: #"{"prompt":"A mountain"}"#)
        )
        let result = succeeded
            ? "Generated one image."
            : "Error executing generate_image: Image generation failed."
        let conversation = Conversation(id: conversationId, modelId: principal.id, messages: [
            ChatMessage(role: .user, content: "Draw a mountain"),
            ChatMessage(role: .assistant, content: "", toolCalls: [call]),
            ChatMessage(role: .tool, content: result, toolCallId: call.id, toolName: call.function.name),
            ChatMessage(role: .assistant, content: "Original response", attachments: succeeded ? [image] : [])
        ])
        return try JSONDecoder().decode(Conversation.self, from: JSONEncoder().encode(conversation))
    }

    func regenerationRegistry(_ sut: ChatViewModel) async throws -> ToolRegistry {
        sut.send(.regenerateLastResponse)
        let task = try XCTUnwrap(sut.streamTask)
        await task.value
        return try capturedRegistry()
    }

    func assertGenerationLimit(
        _ registry: ToolRegistry, file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        XCTAssertFalse(registry.definitions.contains { $0.function.name == "generate_image" }, file: file, line: line)
        // A fresh authorization must reach the registered tool, not an unknown tool or a reused permit.
        let invocation = try await authorizedInvocation(
            registry, name: "generate_image", arguments: #"{"prompt":"A lake"}"#
        )
        do {
            _ = try await registry.execute(invocation)
            XCTFail("Expected the generation turn limit", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? GenerateImageTool.ExecutionError, .turnLimitReached, file: file, line: line)
        }
    }

    func assertOneGeneration(
        _ registry: ToolRegistry, file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let previousCount = specialistGeneration.executeCallCount
        XCTAssertTrue(registry.definitions.contains { $0.function.name == "generate_image" }, file: file, line: line)
        let invocation = try await authorizedInvocation(
            registry, name: "generate_image", arguments: #"{"prompt":"A lake"}"#
        )
        let result = try await registry.execute(invocation)
        XCTAssertEqual(result.images, [generatedImage], file: file, line: line)
        try await assertGenerationLimit(registry, file: file, line: line)
        XCTAssertEqual(specialistGeneration.executeCallCount, previousCount + 1, file: file, line: line)
    }

    func assertPrincipalUnchanged(
        _ sut: ChatViewModel, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let state = try loadedState(sut)
        XCTAssertEqual(state.selectedModel, principal, file: file, line: line)
        XCTAssertEqual(state.conversation?.modelId, principal.id, file: file, line: line)
        XCTAssertEqual(settings.getSelectedModelId(), principal.id, file: file, line: line)
        XCTAssertNil(saveSelectedModel.savedModelId, file: file, line: line)
    }
}
