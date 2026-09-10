//
//  ChatViewModelImageToolsTests+Streaming.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

extension ChatViewModelImageToolsTests {
    func test_send_withoutFunctionCalling_usesRegularStreamWithoutSpecialists() async throws {
        // Given
        let sut = makeViewModel(model: LLMModel(id: "text-without-tools"), pending: [imageAttachment()])

        // When
        try await sendMessage(sut)

        // Then
        XCTAssertEqual(stream.receivedMessages.count, 1)
        XCTAssertEqual(agent.executeCallCount, 0)
        XCTAssertNil(agent.receivedToolContext)
        XCTAssertNil(apiClient.lastRequestBody)
        XCTAssertEqual(specialistGeneration.executeCallCount, 0)
        XCTAssertEqual(nativeGeneration.executeCallCount, 0)
    }

    func test_send_nativeDedicatedGeneration_usesExistingUseCaseNotToolSpecialist() async throws {
        // Given
        let model = LLMModel(id: "native-dedicated", mode: .imageGeneration)
        let sut = makeViewModel(model: model)

        // When
        try await sendMessage(sut, prompt: "A mountain")

        // Then
        XCTAssertEqual(nativeGeneration.models, [model.id])
        XCTAssertEqual(nativeGeneration.prompts, ["A mountain"])
        XCTAssertEqual(specialistGeneration.executeCallCount, 0)
        XCTAssertEqual(agent.executeCallCount, 0)
        XCTAssertTrue(stream.receivedMessages.isEmpty)
        XCTAssertNil(apiClient.lastRequestBody)
        let state = try loadedState(sut)
        XCTAssertEqual(state.selectedModel, model)
        XCTAssertEqual(state.messages.last?.attachments.first?.mimeType, generatedImage.mimeType)
        XCTAssertEqual(state.messages.last?.attachments.first?.transientData, generatedImage.data)
        XCTAssertEqual(save.savedConversations.last?.modelId, model.id)
    }

    func test_send_nativeMultimodalChat_usesAgentAndOriginalImagesWithoutSpecialist() async throws {
        // Given
        let model = LLMModel(id: "native-multimodal", capabilities: [.functionCalling, .vision, .imageGeneration])
        let image = imageAttachment()
        let sut = makeViewModel(model: model, pending: [image])
        agent.events = [.generatedImage(generatedImage), .completed]

        // When
        try await sendMessage(sut)

        // Then
        XCTAssertEqual(agent.executeCallCount, 1)
        XCTAssertTrue(stream.receivedMessages.isEmpty)
        XCTAssertEqual(nativeGeneration.executeCallCount, 0)
        XCTAssertEqual(specialistGeneration.executeCallCount, 0)
        XCTAssertNil(apiClient.lastRequestBody)
        XCTAssertTrue(Set(agent.receivedToolNames).isDisjoint(with: ["analyze_images", "generate_image"]))
        XCTAssertEqual(agent.receivedMessages.first?.last?.attachments, [image])
        XCTAssertEqual(try loadedState(sut).selectedModel, model)
        XCTAssertEqual(try loadedState(sut).messages.last?.attachments.first?.mimeType, generatedImage.mimeType)
        XCTAssertEqual(try XCTUnwrap(agent.receivedToolContext).additionalExecutionTime, .seconds(600))
    }

    func test_send_generatedImageEvent_attachesMIMEAndPersistsBeforeFinalText() async throws {
        // Given
        let sut = makeViewModel()
        agent.events = [.generatedImage(generatedImage), .token("Here is your image"), .completed]

        // When
        try await sendMessage(sut)

        // Then
        let state = try loadedState(sut)
        let assistant = try XCTUnwrap(state.messages.last)
        let attachment = try XCTUnwrap(assistant.attachments.first)
        XCTAssertEqual(assistant.role, .assistant)
        XCTAssertEqual(assistant.content, "Here is your image")
        XCTAssertEqual(assistant.attachments.count, 1)
        XCTAssertEqual(attachment.type, .image)
        XCTAssertEqual(attachment.mimeType, "image/webp")
        XCTAssertEqual(attachment.transientData, generatedImage.data)
        let checkpoint = try XCTUnwrap(save.savedConversations.first { $0.messages.last?.attachments.isEmpty == false })
        XCTAssertEqual(checkpoint.messages.last?.content, "")
        XCTAssertEqual(checkpoint.messages.last?.attachments, [attachment])
        XCTAssertEqual(save.savedConversations.last?.messages.last, assistant)
        XCTAssertEqual(save.savedConversations.last?.modelId, principal.id)
        XCTAssertEqual(state.selectedModel, principal)
        XCTAssertEqual(settings.getSelectedModelId(), principal.id)
        XCTAssertFalse(state.isStreaming)
        XCTAssertNil(state.errorMessage)
        XCTAssertEqual(background.completionResults, [true])
    }

    func test_send_generatedImageThenFinalFailure_keepsAndPersistsImageOnlyAssistant() async throws {
        // Given
        let sut = makeViewModel()
        agent.events = [.generatedImage(generatedImage)]
        agent.error = APIError.serverUnreachable
        var didSaveImageBeforeFailure = false
        save.executeHandler = { [weak sut] conversation, _ in
            if conversation.messages.last?.attachments.isEmpty == false,
               let sut, case .loaded(let current) = sut.state, current.isStreaming, current.errorMessage == nil {
                didSaveImageBeforeFailure = true
            }
            return conversation
        }

        // When
        try await sendMessage(sut)

        // Then
        let state = try loadedState(sut)
        let assistant = try XCTUnwrap(state.messages.last)
        XCTAssertTrue(didSaveImageBeforeFailure)
        XCTAssertEqual(assistant.role, .assistant)
        XCTAssertTrue(assistant.content.isEmpty)
        XCTAssertEqual(assistant.attachments.count, 1)
        XCTAssertEqual(assistant.attachments.first?.mimeType, generatedImage.mimeType)
        XCTAssertEqual(assistant.attachments.first?.transientData, generatedImage.data)
        XCTAssertEqual(save.savedConversations.last?.messages.last, assistant)
        XCTAssertEqual(save.savedConversations.last?.modelId, principal.id)
        XCTAssertEqual(state.selectedModel, principal)
        XCTAssertNotNil(state.errorMessage)
        XCTAssertFalse(state.isStreaming)
        XCTAssertEqual(background.completionResults, [false])
    }

    func test_send_generatedImageInPrivateChat_keepsTransientImageWithoutSaving() async throws {
        // Given
        let sut = makeViewModel(isPrivate: true)
        agent.events = [.generatedImage(generatedImage), .completed]

        // When
        try await sendMessage(sut)

        // Then
        let state = try loadedState(sut)
        XCTAssertEqual(state.messages.last?.attachments.first?.transientData, generatedImage.data)
        XCTAssertEqual(state.messages.last?.attachments.first?.mimeType, generatedImage.mimeType)
        XCTAssertEqual(state.messages.last?.attachments.first?.fileRelativePath, "")
        XCTAssertEqual(state.selectedModel, principal)
        XCTAssertNil(state.conversation)
        XCTAssertEqual(save.executeCallCount, 0)
        XCTAssertTrue(attachments.savedAttachments.isEmpty)
        XCTAssertFalse(state.isStreaming)
        XCTAssertNil(state.errorMessage)
    }

    func test_send_generatedImageThenFailureInPrivateChat_keepsImageWithoutSaving() async throws {
        // Given
        let sut = makeViewModel(isPrivate: true)
        agent.events = [.generatedImage(generatedImage)]
        agent.error = APIError.serverUnreachable

        // When
        try await sendMessage(sut)

        // Then
        let state = try loadedState(sut)
        XCTAssertEqual(state.messages.last?.role, .assistant)
        XCTAssertEqual(state.messages.last?.attachments.first?.transientData, generatedImage.data)
        XCTAssertEqual(state.messages.last?.attachments.first?.mimeType, generatedImage.mimeType)
        XCTAssertEqual(state.selectedModel, principal)
        XCTAssertNil(state.conversation)
        XCTAssertEqual(save.executeCallCount, 0)
        XCTAssertTrue(attachments.savedAttachments.isEmpty)
        XCTAssertNotNil(state.errorMessage)
        XCTAssertFalse(state.isStreaming)
    }

    func test_send_generationToolAvailable_addsSixHundredSecondsToAgentBudget() async throws {
        // Given
        let sut = makeViewModel()

        // When
        try await sendMessage(sut)

        // Then
        XCTAssertTrue(agent.receivedToolNames.contains("generate_image"))
        XCTAssertEqual(try XCTUnwrap(agent.receivedToolContext).additionalExecutionTime, .seconds(600))
        XCTAssertEqual(specialistGeneration.executeCallCount, 0)
    }

    func test_send_analysisOnly_doesNotExtendAgentBudget() async throws {
        // Given
        settings.setSelectedImageGenerationModelId(nil)
        let sut = makeViewModel(pending: [imageAttachment()])

        // When
        try await sendMessage(sut)

        // Then
        XCTAssertTrue(agent.receivedToolNames.contains("analyze_images"))
        XCTAssertFalse(agent.receivedToolNames.contains("generate_image"))
        XCTAssertEqual(try XCTUnwrap(agent.receivedToolContext).additionalExecutionTime, .zero)
    }

    func test_send_noVisualTools_doesNotExtendAgentBudget() async throws {
        // Given
        settings.setSelectedImageGenerationModelId(nil)
        let sut = makeViewModel()

        // When
        try await sendMessage(sut)

        // Then
        XCTAssertTrue(Set(agent.receivedToolNames).isDisjoint(with: ["analyze_images", "generate_image"]))
        XCTAssertEqual(try XCTUnwrap(agent.receivedToolContext).additionalExecutionTime, .zero)
    }
}
