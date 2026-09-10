//
//  ChatViewModelImageToolsTests+Execution.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

extension ChatViewModelImageToolsTests {
    func test_generateImage_dedicatedSpecialist_usesInjectedGenerationWithoutChangingPrincipal() async throws {
        // Given
        let sut = makeViewModel()
        try await sendMessage(sut, prompt: "Draw a cat")
        let registry = try capturedRegistry()
        let invocation = try await authorizedInvocation(
            registry, name: "generate_image", arguments: #"{"prompt":"A cat"}"#
        )

        // When
        let result = try await registry.execute(invocation)

        // Then
        XCTAssertEqual(result.images, [generatedImage])
        XCTAssertEqual(specialistGeneration.models, [generator.id])
        XCTAssertEqual(specialistGeneration.prompts, ["A cat"])
        XCTAssertEqual(specialistGeneration.attachments, [[]])
        XCTAssertEqual(nativeGeneration.executeCallCount, 0)
        XCTAssertNil(apiClient.lastRequestBody)
        XCTAssertEqual(try loadedState(sut).selectedModel, principal)
        XCTAssertEqual(try loadedState(sut).conversation?.modelId, principal.id)
        XCTAssertEqual(settings.getSelectedModelId(), principal.id)
        XCTAssertNil(saveSelectedModel.savedModelId)
    }

    func test_generateImage_chatSpecialist_usesInjectedGenerationWithSelectedSpecialistID() async throws {
        // Given
        let chatGenerator = LLMModel(id: "chat-specialist", capabilities: [.imageGeneration])
        settings.setSelectedImageGenerationModelId(chatGenerator.id)
        let sut = makeViewModel(extraModels: [chatGenerator])
        try await sendMessage(sut)
        let registry = try capturedRegistry()
        let invocation = try await authorizedInvocation(
            registry, name: "generate_image", arguments: #"{"prompt":"A lake"}"#
        )

        // When
        let result = try await registry.execute(invocation)

        // Then
        XCTAssertEqual(result.images, [generatedImage])
        XCTAssertEqual(specialistGeneration.models, [chatGenerator.id])
        XCTAssertEqual(nativeGeneration.executeCallCount, 0)
        XCTAssertNil(apiClient.lastRequestBody)
        XCTAssertEqual(try loadedState(sut).selectedModel, principal)
    }

    func test_analyzeImages_restoredHistoryAndTransientInput_resolvesIDsAndPreservesHistory() async throws {
        // Given
        let conversationId = UUID()
        let stored = imageAttachment(conversationId: conversationId, data: nil)
        let transient = imageAttachment(data: Data([7, 8, 9]))
        let historical = ChatMessage(role: .user, content: "Earlier photo", attachments: [stored])
        let conversation = Conversation(id: conversationId, modelId: principal.id, messages: [historical])
        let restored = try JSONDecoder().decode(Conversation.self, from: JSONEncoder().encode(conversation))
        var loadedIds: [UUID] = []
        attachments.loadHandler = { attachment in
            loadedIds.append(attachment.id)
            return Data([10, 11])
        }
        let sut = makeViewModel(pending: [transient], conversation: restored)
        try await sendMessage(sut)
        let registry = try capturedRegistry()
        let definition = try XCTUnwrap(registry.definitions.first { $0.function.name == "analyze_images" })
        let invocation = try await authorizedInvocation(
            registry, name: "analyze_images", arguments: analysisArguments(ids: [transient.id, stored.id])
        )

        // When
        let result = try await registry.execute(invocation)

        // Then
        XCTAssertNil(definition.function.parameters.properties["attachment_ids"]?.items?.enum)
        let list = try await authorizedInvocation(registry, name: "list_image_attachments", arguments: "{}")
        let inventory = try await registry.execute(list)
        XCTAssertTrue(inventory.text.contains(stored.id.uuidString))
        XCTAssertTrue(inventory.text.contains(transient.id.uuidString))
        XCTAssertEqual(loadedIds, [stored.id])
        let request = try XCTUnwrap(apiClient.lastRequestBody as? ChatCompletionRequest)
        XCTAssertEqual(request.model, vision.id)
        XCTAssertEqual(request.messages.map(\.role), ["system", "user"])
        XCTAssertFalse(request.stream)
        XCTAssertNil(request.tools)
        let specialistMessage = try XCTUnwrap(request.messages.last)
        guard case .multimodal(let parts) = specialistMessage.content else {
            return XCTFail("Expected specialist image content")
        }
        XCTAssertEqual(parts.compactMap { $0.imageUrl?.url }, [
            "data:image/jpeg;base64,\(Data([7, 8, 9]).base64EncodedString())",
            "data:image/jpeg;base64,\(Data([10, 11]).base64EncodedString())"
        ])
        XCTAssertTrue(result.text.contains(vision.id))
        let state = try loadedState(sut)
        XCTAssertEqual(state.messages.first, restored.messages.first)
        XCTAssertEqual(state.messages.dropFirst().first?.attachments, [transient])
        XCTAssertEqual(save.savedConversations.last?.messages.first, restored.messages.first)
        XCTAssertEqual(state.selectedModel, principal)
        XCTAssertTrue(attachments.savedAttachments.isEmpty)
        XCTAssertEqual(specialistGeneration.executeCallCount, 0)
    }

    func test_send_textPrincipal_sendsOnlyImageReferencesButPersistsOriginalAttachments() async throws {
        // Given
        let image = imageAttachment()
        let sut = makeViewModel(pending: [image])

        // When
        try await sendMessage(sut)

        // Then
        let messages = try XCTUnwrap(agent.receivedMessages.first)
        let user = try XCTUnwrap(messages.last { $0.role == .user })
        XCTAssertTrue(user.attachments.isEmpty)
        XCTAssertTrue(user.content.contains(image.id.uuidString))
        XCTAssertTrue(user.content.contains("image_attachment_ids"))
        XCTAssertEqual(try loadedState(sut).messages.first?.attachments, [image])
        XCTAssertEqual(save.savedConversations.last?.messages.first?.attachments, [image])
        XCTAssertEqual(Set(agent.receivedToolNames).intersection(["analyze_images", "generate_image"]),
                       ["analyze_images", "generate_image"])
        XCTAssertEqual(try XCTUnwrap(agent.receivedToolContext).additionalExecutionTime, .seconds(600))
    }

    func test_analyzeImages_unknownReference_rejectsBeforeLoadingOrRequesting() async throws {
        // Given
        let sut = makeViewModel(pending: [imageAttachment()])
        try await sendMessage(sut)
        let registry = try capturedRegistry()
        let invocation = try await authorizedInvocation(
            registry, name: "analyze_images", arguments: analysisArguments(ids: [UUID()])
        )
        attachments.loadHandler = { _ in
            XCTFail("Unknown IDs must not reach attachment storage")
            return Data([1])
        }

        // When / Then
        do {
            _ = try await registry.execute(invocation)
            XCTFail("Expected an unknown attachment error")
        } catch {
            XCTAssertEqual(error as? AnalyzeImagesTool.ExecutionError, .unknownAttachment)
        }
        XCTAssertNil(apiClient.lastRequestBody)
        XCTAssertEqual(specialistGeneration.executeCallCount, 0)
    }

    func test_specialistDefaults_changingVision_keepsGenerationAndPrincipalIndependent() async throws {
        // Given
        let otherVision = LLMModel(id: "other-vision", capabilities: [.vision])
        let image = imageAttachment()
        let sut = makeViewModel(pending: [image], extraModels: [otherVision])
        settings.setSelectedVisionModelId(otherVision.id)
        try await sendMessage(sut)
        let registry = try capturedRegistry()
        let analyze = try await authorizedInvocation(
            registry, name: "analyze_images", arguments: analysisArguments(ids: [image.id])
        )
        let generate = try await authorizedInvocation(
            registry, name: "generate_image", arguments: #"{"prompt":"A cat"}"#
        )

        // When
        _ = try await registry.execute(analyze)
        _ = try await registry.execute(generate)

        // Then
        XCTAssertEqual((apiClient.lastRequestBody as? ChatCompletionRequest)?.model, otherVision.id)
        XCTAssertEqual(specialistGeneration.models, [generator.id])
        XCTAssertEqual(settings.getSelectedImageGenerationModelId(), generator.id)
        XCTAssertEqual(settings.getSelectedModelId(), principal.id)
        XCTAssertEqual(try loadedState(sut).selectedModel, principal)
    }

    func test_specialistDefaults_changingGeneration_keepsVisionAndPrincipalIndependent() async throws {
        // Given
        let otherGenerator = LLMModel(id: "other-generator", mode: .imageGeneration)
        let image = imageAttachment()
        let sut = makeViewModel(pending: [image], extraModels: [otherGenerator])
        settings.setSelectedImageGenerationModelId(otherGenerator.id)
        try await sendMessage(sut)
        let registry = try capturedRegistry()
        let analyze = try await authorizedInvocation(
            registry, name: "analyze_images", arguments: analysisArguments(ids: [image.id])
        )
        let generate = try await authorizedInvocation(
            registry, name: "generate_image", arguments: #"{"prompt":"A cat"}"#
        )

        // When
        _ = try await registry.execute(analyze)
        _ = try await registry.execute(generate)

        // Then
        XCTAssertEqual((apiClient.lastRequestBody as? ChatCompletionRequest)?.model, vision.id)
        XCTAssertEqual(specialistGeneration.models, [otherGenerator.id])
        XCTAssertEqual(settings.getSelectedVisionModelId(), vision.id)
        XCTAssertEqual(settings.getSelectedModelId(), principal.id)
        XCTAssertEqual(try loadedState(sut).selectedModel, principal)
    }
}
