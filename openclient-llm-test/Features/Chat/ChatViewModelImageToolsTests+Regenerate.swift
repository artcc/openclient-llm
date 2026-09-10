//
//  ChatViewModelImageToolsTests+Regenerate.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
extension ChatViewModelImageToolsTests {
    func test_regenerateLastResponse_toolImageWithAgent_reusesTranscriptAndImage() async throws {
        // Given
        let conversation = imageToolConversation()
        let original = try XCTUnwrap(conversation.messages.last)
        let sut = makeViewModel(conversation: conversation)
        agent.events = [.token("Regenerated text"), .completed]

        // When
        sut.send(.regenerateLastResponse)
        let task = try XCTUnwrap(sut.streamTask)
        let placeholder = try XCTUnwrap(loadedState(sut).messages.last)
        XCTAssertEqual(placeholder.attachments, original.attachments)
        XCTAssertTrue(placeholder.content.isEmpty)
        await task.value

        // Then
        let state = try loadedState(sut)
        let response = try XCTUnwrap(state.messages.last)
        XCTAssertNotEqual(response.id, original.id)
        XCTAssertEqual(response.content, "Regenerated text")
        XCTAssertEqual(response.attachments, original.attachments)
        XCTAssertEqual(response.attachments.first?.id, original.attachments.first?.id)
        XCTAssertEqual(response.attachments.first?.mimeType, "image/webp")
        XCTAssertEqual(Array(state.messages.dropLast()), Array(conversation.messages.dropLast()))
        XCTAssertEqual(
            agent.receivedMessages.first?.filter { $0.role != .system },
            Array(conversation.messages.dropLast())
        )
        XCTAssertEqual(save.savedConversations.last?.messages, state.messages)
        XCTAssertEqual(agent.executeCallCount, 1)
        XCTAssertEqual(specialistGeneration.executeCallCount, 0)
        XCTAssertEqual(nativeGeneration.executeCallCount, 0)
        XCTAssertFalse(state.isStreaming)
        XCTAssertNil(state.errorMessage)
    }

    func test_regenerateLastResponse_changedToTextModel_reusesToolImageWithRegularStream() async throws {
        // Given
        let conversation = imageToolConversation()
        let textModel = LLMModel(id: "text-without-tools")
        let sut = makeViewModel(conversation: conversation, extraModels: [textModel])
        stream.chunks = [.token("New text"), .token(" response")]
        sut.send(.modelSelected(textModel))
        _ = await sut.persistenceTask?.value

        // When
        try await regenerateResponse(sut)

        // Then
        let state = try loadedState(sut)
        XCTAssertEqual(state.selectedModel, textModel)
        XCTAssertEqual(state.messages.last?.content, "New text response")
        XCTAssertEqual(state.messages.last?.attachments, conversation.messages.last?.attachments)
        XCTAssertEqual(Array(state.messages.dropLast()), Array(conversation.messages.dropLast()))
        XCTAssertEqual(
            stream.receivedMessages.first?.filter { $0.role != .system },
            Array(conversation.messages.dropLast())
        )
        XCTAssertEqual(save.savedConversations.last?.messages, state.messages)
        XCTAssertEqual(agent.executeCallCount, 0)
        XCTAssertEqual(specialistGeneration.executeCallCount, 0)
        XCTAssertEqual(nativeGeneration.executeCallCount, 0)
    }

    func test_regenerateLastResponse_repeatedAgentFailure_keepsAndPersistsToolImage() async throws {
        // Given
        let conversation = imageToolConversation()
        let sut = makeViewModel(conversation: conversation)
        agent.events = []
        agent.error = APIError.serverUnreachable

        for _ in 0..<2 {
            // When
            try await regenerateResponse(sut)

            // Then
            let state = try loadedState(sut)
            XCTAssertEqual(state.messages.last?.role, .assistant)
            XCTAssertEqual(state.messages.last?.content, "")
            XCTAssertEqual(state.messages.last?.attachments, conversation.messages.last?.attachments)
            XCTAssertEqual(Array(state.messages.dropLast()), Array(conversation.messages.dropLast()))
            XCTAssertEqual(save.savedConversations.last?.messages, state.messages)
            XCTAssertFalse(state.isStreaming)
            XCTAssertNotNil(state.errorMessage)
        }
        XCTAssertEqual(agent.executeCallCount, 2)
        XCTAssertEqual(specialistGeneration.executeCallCount, 0)
        XCTAssertEqual(nativeGeneration.executeCallCount, 0)
    }

    func test_regenerateLastResponse_regularStreamFailure_keepsToolImage() async throws {
        // Given
        let conversation = imageToolConversation()
        let sut = makeViewModel(model: LLMModel(id: "text-without-tools"), conversation: conversation)
        stream.chunks = []
        stream.error = APIError.serverUnreachable

        // When
        try await regenerateResponse(sut)

        // Then
        let state = try loadedState(sut)
        XCTAssertEqual(state.messages.last?.role, .assistant)
        XCTAssertEqual(state.messages.last?.content, "")
        XCTAssertEqual(state.messages.last?.attachments, conversation.messages.last?.attachments)
        XCTAssertEqual(Array(state.messages.dropLast()), Array(conversation.messages.dropLast()))
        XCTAssertEqual(save.savedConversations.last?.messages, state.messages)
        XCTAssertFalse(state.isStreaming)
        XCTAssertNotNil(state.errorMessage)
        XCTAssertEqual(specialistGeneration.executeCallCount, 0)
        XCTAssertEqual(nativeGeneration.executeCallCount, 0)
    }

    func test_regenerateLastResponse_stoppedByUser_keepsAndPersistsToolImage() async throws {
        // Given
        let conversation = imageToolConversation()
        let sut = makeViewModel(conversation: conversation)
        let started = expectation(description: "Regeneration started")
        agent.events = []
        agent.waitsForCancellation = true
        agent.onExecute = { started.fulfill() }

        // When
        sut.send(.regenerateLastResponse)
        let task = try XCTUnwrap(sut.streamTask)
        await fulfillment(of: [started], timeout: 1)
        sut.send(.stopStreamingTapped)
        await task.value
        _ = await sut.persistenceTask?.value

        // Then
        let state = try loadedState(sut)
        XCTAssertEqual(state.messages.last?.content, "")
        XCTAssertEqual(state.messages.last?.attachments, conversation.messages.last?.attachments)
        XCTAssertEqual(Array(state.messages.dropLast()), Array(conversation.messages.dropLast()))
        XCTAssertEqual(save.savedConversations.last?.messages, state.messages)
        XCTAssertFalse(state.isStreaming)
        XCTAssertNil(state.errorMessage)
        XCTAssertEqual(specialistGeneration.executeCallCount, 0)
        XCTAssertEqual(nativeGeneration.executeCallCount, 0)
    }

    func test_regenerateLastResponse_agentCancellation_keepsToolImageWithoutError() async throws {
        // Given
        let conversation = imageToolConversation()
        let sut = makeViewModel(conversation: conversation)
        agent.events = []
        agent.error = CancellationError()

        // When
        try await regenerateResponse(sut)
        _ = await sut.persistenceTask?.value

        // Then
        let state = try loadedState(sut)
        XCTAssertEqual(state.messages.last?.attachments, conversation.messages.last?.attachments)
        XCTAssertEqual(Array(state.messages.dropLast()), Array(conversation.messages.dropLast()))
        XCTAssertEqual(save.savedConversations.last?.messages, state.messages)
        XCTAssertFalse(state.isStreaming)
        XCTAssertNil(state.errorMessage)
    }

    func test_regenerateLastResponse_toolGenerationOnlyInOlderTurn_doesNotRetainLatestNativeImage() async throws {
        // Given
        var conversation = imageToolConversation()
        let olderTurn = conversation.messages
        let latestImage = imageAttachment()
        conversation.messages += [
            ChatMessage(role: .user, content: "A new image"),
            ChatMessage(role: .assistant, content: "Native image", attachments: [latestImage])
        ]
        let nativeModel = LLMModel(id: "native-chat", capabilities: [.functionCalling, .imageGeneration])
        let sut = makeViewModel(model: nativeModel, conversation: conversation)
        agent.events = [.generatedImage(generatedImage), .completed]

        // When
        try await regenerateResponse(sut)

        // Then
        let state = try loadedState(sut)
        let images = try XCTUnwrap(state.messages.last).attachments
        XCTAssertEqual(images.count, 1)
        XCTAssertNotEqual(images.first?.id, latestImage.id)
        XCTAssertEqual(images.first?.transientData, generatedImage.data)
        XCTAssertEqual(Array(state.messages.prefix(olderTurn.count)), olderTurn)
        XCTAssertEqual(specialistGeneration.executeCallCount, 0)
    }

    func test_regenerateLastResponse_unrelatedToolResult_doesNotRetainImage() async throws {
        // Given
        var conversation = imageToolConversation()
        conversation.messages[1].toolCalls = [ToolCall(
            id: "call-image", type: "function", function: .init(name: "get_current_datetime", arguments: "{}")
        )]
        conversation.messages[2].toolName = "get_current_datetime"
        conversation.messages[2].content = "generate_image is mentioned, not executed"
        let sut = makeViewModel(conversation: conversation)

        // When
        try await regenerateResponse(sut)

        // Then
        let state = try loadedState(sut)
        XCTAssertEqual(state.messages.last?.attachments, [])
        XCTAssertEqual(state.messages.last?.content, "Response")
        XCTAssertEqual(Array(state.messages.dropLast()), Array(conversation.messages.dropLast()))
    }

    func test_regenerateLastResponse_toolResultWithoutImage_doesNotRetainOtherAttachments() async throws {
        // Given
        var conversation = imageToolConversation()
        conversation.messages[3].attachments = [ChatMessage.Attachment(
            type: .pdf, fileName: "document.pdf", mimeType: "application/pdf", fileRelativePath: ""
        )]
        let sut = makeViewModel(conversation: conversation)

        // When
        try await regenerateResponse(sut)

        // Then
        let state = try loadedState(sut)
        XCTAssertEqual(state.messages.last?.attachments, [])
        XCTAssertEqual(state.messages.last?.content, "Response")
        XCTAssertEqual(Array(state.messages.dropLast()), Array(conversation.messages.dropLast()))
    }

    func test_regenerateLastResponse_ordinaryText_replacesOnlyAssistantText() async throws {
        // Given
        let conversation = Conversation(modelId: "text", messages: [
            ChatMessage(role: .user, content: "Hello"),
            ChatMessage(role: .assistant, content: "Original text")
        ])
        let sut = makeViewModel(model: LLMModel(id: "text"), conversation: conversation)

        // When
        try await regenerateResponse(sut)

        // Then
        let state = try loadedState(sut)
        XCTAssertEqual(state.messages.count, 2)
        XCTAssertEqual(state.messages.first, conversation.messages.first)
        XCTAssertNotEqual(state.messages.last?.id, conversation.messages.last?.id)
        XCTAssertEqual(state.messages.last?.content, "Response")
        XCTAssertEqual(state.messages.last?.attachments, [])
        XCTAssertEqual(stream.receivedMessages.count, 1)
        XCTAssertEqual(agent.executeCallCount, 0)
        XCTAssertEqual(nativeGeneration.executeCallCount, 0)
    }

    func test_regenerateLastResponse_dedicatedGeneration_replacesImageUsingOriginalPrompt() async throws {
        // Given
        let originalImage = imageAttachment()
        let conversation = Conversation(modelId: generator.id, messages: [
            ChatMessage(role: .user, content: "A mountain"),
            ChatMessage(role: .assistant, content: "", attachments: [originalImage])
        ])
        let sut = makeViewModel(model: generator, conversation: conversation)

        // When
        try await regenerateResponse(sut)

        // Then
        let state = try loadedState(sut)
        let images = try XCTUnwrap(state.messages.last).attachments
        XCTAssertEqual(images.count, 1)
        XCTAssertNotEqual(images.first?.id, originalImage.id)
        XCTAssertEqual(images.first?.mimeType, generatedImage.mimeType)
        XCTAssertEqual(images.first?.transientData, generatedImage.data)
        XCTAssertEqual(nativeGeneration.prompts, ["A mountain"])
        XCTAssertEqual(nativeGeneration.models, [generator.id])
        XCTAssertEqual(nativeGeneration.attachments, [[]])
        XCTAssertEqual(nativeGeneration.executeCallCount, 1)
        XCTAssertEqual(specialistGeneration.executeCallCount, 0)
        XCTAssertEqual(agent.executeCallCount, 0)
        XCTAssertTrue(stream.receivedMessages.isEmpty)
    }

    func test_regenerateLastResponse_changedToNativeChat_restartsTurnWithOneNewImage() async throws {
        // Given
        let conversation = imageToolConversation()
        let nativeModel = LLMModel(id: "native-chat", capabilities: [.functionCalling, .imageGeneration])
        let sut = makeViewModel(conversation: conversation, extraModels: [nativeModel])
        agent.events = [.generatedImage(generatedImage), .token("New native image"), .completed]
        sut.send(.modelSelected(nativeModel))
        _ = await sut.persistenceTask?.value

        // When
        try await regenerateResponse(sut)

        // Then
        let state = try loadedState(sut)
        let images = try XCTUnwrap(state.messages.last).attachments
        XCTAssertEqual(state.selectedModel, nativeModel)
        XCTAssertEqual(images.count, 1)
        XCTAssertNotEqual(images.first?.id, conversation.messages.last?.attachments.first?.id)
        XCTAssertEqual(images.last?.mimeType, generatedImage.mimeType)
        XCTAssertEqual(images.last?.transientData, generatedImage.data)
        XCTAssertEqual(Array(state.messages.dropLast()), Array(conversation.messages.prefix(1)))
        XCTAssertEqual(save.savedConversations.last?.messages, state.messages)
        XCTAssertFalse(agent.receivedToolNames.contains("generate_image"))
        XCTAssertEqual(specialistGeneration.executeCallCount, 0)
        XCTAssertEqual(nativeGeneration.executeCallCount, 0)
    }

    func test_regenerateLastResponse_changedToDedicatedModel_restartsTurnWithOneNewImage() async throws {
        // Given
        let conversation = imageToolConversation()
        let sut = makeViewModel(conversation: conversation)
        sut.send(.modelSelected(generator))
        _ = await sut.persistenceTask?.value

        // When
        try await regenerateResponse(sut)

        // Then
        let state = try loadedState(sut)
        let images = try XCTUnwrap(state.messages.last).attachments
        XCTAssertEqual(state.selectedModel, generator)
        XCTAssertEqual(images.count, 1)
        XCTAssertNotEqual(images.first?.id, conversation.messages.last?.attachments.first?.id)
        XCTAssertEqual(images.last?.transientData, generatedImage.data)
        XCTAssertEqual(Array(state.messages.dropLast()), Array(conversation.messages.prefix(1)))
        XCTAssertEqual(save.savedConversations.last?.messages, state.messages)
        XCTAssertEqual(nativeGeneration.prompts, ["A mountain"])
        XCTAssertEqual(nativeGeneration.models, [generator.id])
        XCTAssertEqual(nativeGeneration.executeCallCount, 1)
        XCTAssertEqual(specialistGeneration.executeCallCount, 0)
        XCTAssertEqual(agent.executeCallCount, 0)
    }

    func test_regenerateLastResponse_repeatedNativeRegeneration_doesNotAccumulateImages() async throws {
        // Given
        let nativeModel = LLMModel(id: "native-chat", capabilities: [.functionCalling, .imageGeneration])
        agent.events = [.generatedImage(generatedImage), .completed]
        for model in [nativeModel, generator] {
            let conversation = imageToolConversation()
            let sut = makeViewModel(conversation: conversation, extraModels: [nativeModel])
            sut.send(.modelSelected(model))
            _ = await sut.persistenceTask?.value

            // When
            try await regenerateResponse(sut)
            let firstImages = try XCTUnwrap(loadedState(sut).messages.last).attachments
            try await regenerateResponse(sut)

            // Then
            let state = try loadedState(sut)
            let secondImages = try XCTUnwrap(state.messages.last).attachments
            XCTAssertEqual(firstImages.count, 1)
            XCTAssertEqual(secondImages.count, 1)
            XCTAssertNotEqual(secondImages.first?.id, firstImages.first?.id)
            XCTAssertNotEqual(secondImages.first?.id, conversation.messages.last?.attachments.first?.id)
            XCTAssertEqual(secondImages.first?.mimeType, generatedImage.mimeType)
            XCTAssertEqual(secondImages.first?.transientData, generatedImage.data)
            XCTAssertEqual(Array(state.messages.dropLast()), Array(conversation.messages.prefix(1)))
            XCTAssertEqual(save.savedConversations.last?.messages, state.messages)
        }
        XCTAssertEqual(specialistGeneration.executeCallCount, 0)
    }

    func test_regenerateLastResponse_nativeChatRequest_removesOnlyLatestToolTranscript() async throws {
        // Given
        let olderTurn = imageToolConversation().messages
        var conversation = imageToolConversation()
        let latestUser = try XCTUnwrap(conversation.messages.first)
        conversation.messages.insert(contentsOf: olderTurn, at: 0)
        let nativeModel = LLMModel(id: "native-chat", capabilities: [.functionCalling, .vision, .imageGeneration])
        let sut = makeViewModel(conversation: conversation, extraModels: [nativeModel])
        agent.events = [.generatedImage(generatedImage), .completed]
        sut.send(.modelSelected(nativeModel))
        _ = await sut.persistenceTask?.value

        // When
        try await regenerateResponse(sut)

        // Then
        let request = try XCTUnwrap(agent.receivedMessages.first).filter { $0.role != .system }
        XCTAssertEqual(request, olderTurn + [latestUser])
        XCTAssertEqual(request.last, latestUser)
        let state = try loadedState(sut)
        XCTAssertEqual(Array(state.messages.dropLast()), olderTurn + [latestUser])
        XCTAssertEqual(state.messages.last?.attachments.count, 1)
        XCTAssertEqual(save.savedConversations.last?.messages, state.messages)
    }
}

// MARK: - Helpers

private extension ChatViewModelImageToolsTests {
    func imageToolConversation() -> Conversation {
        let conversationId = UUID()
        let imageId = UUID()
        let image = ChatMessage.Attachment(
            id: imageId, type: .image, fileName: "mountain.webp", mimeType: generatedImage.mimeType,
            fileRelativePath: "Attachments/\(conversationId)/\(imageId).webp", transientData: generatedImage.data
        )
        let call = ToolCall(
            id: "call-image", type: "function",
            function: .init(name: "generate_image", arguments: "{\"prompt\":\"A mountain\"}")
        )
        return Conversation(id: conversationId, modelId: principal.id, messages: [
            ChatMessage(role: .user, content: "A mountain"),
            ChatMessage(role: .assistant, content: "", toolCalls: [call]),
            ChatMessage(
                role: .tool, content: "Image generated successfully and displayed in the chat.",
                toolCallId: call.id, toolName: call.function.name
            ),
            ChatMessage(role: .assistant, content: "Here is your image", attachments: [image])
        ])
    }

    func regenerateResponse(_ sut: ChatViewModel) async throws {
        sut.send(.regenerateLastResponse)
        let task = try XCTUnwrap(sut.streamTask)
        await task.value
    }
}
