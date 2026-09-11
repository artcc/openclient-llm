//
//  ChatViewModelTests+ImageEditing.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 09/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
extension ChatViewModelTests {
    func test_send_imageModelWithVision_forwardsOnlyCurrentAttachments() async throws {
        // Given
        let historical = imageEditingAttachment(data: Data([1]))
        let references = [imageEditingAttachment(data: Data([2])), imageEditingAttachment(data: Data([3]))]
        var loadedState = sut.makeLoadedState(models: [imageEditingModel], pending: nil)
        loadedState.messages = [
            ChatMessage(role: .user, content: "Old prompt", attachments: [historical]),
            ChatMessage(role: .assistant, content: "", attachments: [historical])
        ]
        loadedState.pendingAttachments = references
        loadedState.inputText = "Combine these images"
        sut.state = .loaded(loadedState)
        mockGenerateImage.result = .success(imageEditingResult)

        // When
        sut.send(.sendTapped)
        await sut.streamTask?.value

        // Then
        XCTAssertEqual(mockGenerateImage.prompts, ["Combine these images"])
        XCTAssertEqual(mockGenerateImage.attachments, [references])
        XCTAssertTrue(mockStreamMessage.receivedMessages.isEmpty)
        guard case .loaded(let result) = sut.state else { return XCTFail("Expected loaded state") }
        XCTAssertTrue(result.pendingAttachments.isEmpty)
        XCTAssertEqual(result.messages[result.messages.count - 2].attachments, references)
        XCTAssertEqual(result.messages.last?.attachments.first?.transientData, imageEditingResult.data)
        XCTAssertNil(result.errorMessage)
    }

    func test_send_imageModelWithVisionWithoutNewAttachments_doesNotReuseHistoryImages() async {
        // Given
        var loadedState = sut.makeLoadedState(models: [imageEditingModel], pending: nil)
        loadedState.messages = [
            ChatMessage(role: .user, content: "Old prompt", attachments: [imageEditingAttachment()])
        ]
        loadedState.inputText = "A new image"
        sut.state = .loaded(loadedState)
        mockGenerateImage.result = .success(imageEditingResult)

        // When
        sut.send(.sendTapped)
        await sut.streamTask?.value

        // Then
        XCTAssertEqual(mockGenerateImage.prompts, ["A new image"])
        XCTAssertEqual(mockGenerateImage.attachments, [[]])
    }

    func test_send_invalidImageGenerationInput_preservesDraftAndAttachments() {
        // Given
        let pdf = ChatMessage.Attachment(
            type: .pdf, fileName: "document.pdf", mimeType: "application/pdf", fileRelativePath: ""
        )
        let scenarios = [
            (LLMModel(id: "image-model", mode: .imageGeneration), "Edit", imageEditingAttachment()),
            (imageEditingModel, "Edit", pdf),
            (imageEditingModel, " \n", imageEditingAttachment())
        ]
        for (model, prompt, attachment) in scenarios {
            var loadedState = sut.makeLoadedState(models: [model], pending: nil)
            loadedState.inputText = prompt
            loadedState.pendingAttachments = [attachment]
            sut.state = .loaded(loadedState)

            // When
            sut.send(.sendTapped)

            // Then
            guard case .loaded(let result) = sut.state else { return XCTFail("Expected loaded state") }
            XCTAssertNotNil(result.errorMessage)
            XCTAssertEqual(result.inputText, prompt)
            XCTAssertEqual(result.pendingAttachments, [attachment])
            XCTAssertTrue(result.messages.isEmpty)
            XCTAssertFalse(result.isStreaming)
        }
        XCTAssertEqual(mockGenerateImage.executeCallCount, 0)
        XCTAssertEqual(mockStreamingBackground.beginCallCount, 0)
    }

    func test_regenerate_imageModel_usesOriginalPromptAndAttachments() async {
        // Given
        let references = [imageEditingAttachment()]
        var loadedState = sut.makeLoadedState(models: [imageEditingModel], pending: nil)
        loadedState.messages = [
            ChatMessage(role: .user, content: "Edit this image", attachments: references),
            ChatMessage(role: .assistant, content: "", attachments: [imageEditingAttachment(data: Data([9]))])
        ]
        loadedState.pendingAttachments = [imageEditingAttachment(data: Data([8]))]
        sut.state = .loaded(loadedState)
        mockGenerateImage.result = .success(imageEditingResult)

        // When
        sut.send(.regenerateLastResponse)
        await sut.streamTask?.value

        // Then
        XCTAssertEqual(mockGenerateImage.prompts, ["Edit this image"])
        XCTAssertEqual(mockGenerateImage.attachments, [references])
        guard case .loaded(let result) = sut.state else { return XCTFail("Expected loaded state") }
        XCTAssertEqual(result.pendingAttachments, loadedState.pendingAttachments)
        XCTAssertEqual(result.messages.count, 2)
    }

    func test_editMessage_imageModel_keepsReferencesFromEditedMessage() async {
        // Given
        let reference = imageEditingAttachment()
        let message = ChatMessage(role: .user, content: "Old prompt", attachments: [reference])
        var loadedState = sut.makeLoadedState(models: [imageEditingModel], pending: nil)
        loadedState.messages = [message, ChatMessage(role: .assistant, content: "Old result")]
        sut.state = .loaded(loadedState)
        mockGenerateImage.result = .success(imageEditingResult)

        // When
        sut.send(.editMessage(id: message.id, newContent: "New prompt"))
        await sut.streamTask?.value

        // Then
        XCTAssertEqual(mockGenerateImage.prompts, ["New prompt"])
        XCTAssertEqual(mockGenerateImage.attachments, [[reference]])
    }

    func test_regenerateAndEdit_afterSwitchingToImageModelWithoutVision_preservesHistory() {
        // Given
        let message = ChatMessage(role: .user, content: "Original prompt", attachments: [imageEditingAttachment()])
        var loadedState = sut.makeLoadedState(
            models: [LLMModel(id: "text-to-image", mode: .imageGeneration)], pending: nil
        )
        loadedState.messages = [message, ChatMessage(role: .assistant, content: "Existing response")]
        sut.state = .loaded(loadedState)

        for event in [ChatViewModel.Event.regenerateLastResponse, .editMessage(id: message.id, newContent: "New")] {
            // When
            sut.send(event)

            // Then
            guard case .loaded(let result) = sut.state else { return XCTFail("Expected loaded state") }
            XCTAssertEqual(result.messages, loadedState.messages)
            XCTAssertFalse(result.isStreaming)
            XCTAssertNotNil(result.errorMessage)
        }
        XCTAssertEqual(mockGenerateImage.executeCallCount, 0)
    }

    func test_send_imageEditingFailure_keepsUserReferencesForRetry() async {
        // Given
        let references = [imageEditingAttachment()]
        var loadedState = sut.makeLoadedState(models: [imageEditingModel], pending: nil)
        loadedState.pendingAttachments = references
        loadedState.inputText = "Edit this image"
        sut.state = .loaded(loadedState)
        mockGenerateImage.result = .failure(APIError.httpError(statusCode: 400))

        // When
        sut.send(.sendTapped)
        await sut.streamTask?.value

        // Then
        guard case .loaded(let result) = sut.state else { return XCTFail("Expected loaded state") }
        XCTAssertEqual(result.messages.count, 1)
        XCTAssertEqual(result.messages.first?.attachments, references)
        XCTAssertNotNil(result.errorMessage)
        XCTAssertFalse(result.isStreaming)
        XCTAssertEqual(mockStreamingBackground.completionResults, [false])
    }

    func test_send_imageEditingInPrivateChat_doesNotPersistImages() async {
        // Given
        var loadedState = ChatViewModel.LoadedState(selectedModel: imageEditingModel)
        let references = [imageEditingAttachment()]
        loadedState.pendingAttachments = references
        loadedState.inputText = "Private image edit"
        sut = ChatViewModel(
            isPrivateChat: true,
            state: .loaded(loadedState),
            attachmentRepository: mockAttachmentRepository,
            generateImageUseCase: mockGenerateImage,
            saveConversationUseCase: mockSaveConversation,
            streamingBackgroundUseCase: mockStreamingBackground,
            notifyStreamingCompletedUseCase: mockNotifyStreamingCompleted
        )
        mockGenerateImage.result = .success(imageEditingResult)

        // When
        sut.send(.sendTapped)
        await sut.streamTask?.value

        // Then
        XCTAssertEqual(mockGenerateImage.attachments, [references])
        XCTAssertEqual(mockSaveConversation.executeCallCount, 0)
        XCTAssertTrue(mockAttachmentRepository.savedAttachments.isEmpty)
        guard case .loaded(let result) = sut.state else { return XCTFail("Expected loaded state") }
        XCTAssertNil(result.conversation)
        XCTAssertEqual(result.messages.last?.attachments.first?.transientData, imageEditingResult.data)
    }
}

// MARK: - Private

private extension ChatViewModelTests {
    var imageEditingModel: LLMModel {
        LLMModel(id: "image-model", capabilities: [.vision], mode: .imageGeneration)
    }

    var imageEditingResult: GeneratedImage {
        GeneratedImage(data: Data([4, 5, 6]), mimeType: "image/png", revisedPrompt: nil)
    }

    func imageEditingAttachment(data: Data = Data([1, 2, 3])) -> ChatMessage.Attachment {
        ChatMessage.Attachment(
            type: .image, fileName: "reference.png", mimeType: "image/png", fileRelativePath: "", transientData: data
        )
    }
}
