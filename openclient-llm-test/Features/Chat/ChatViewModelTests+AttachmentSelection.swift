//
//  ChatViewModelTests+AttachmentSelection.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 01/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
extension ChatViewModelTests {
    func test_send_multipleImages_blocksSendingDuringLoadAndPreservesSelectionOrder() async throws {
        // Given
        sut.state = .loaded(.init(inputText: "Compare", selectedModel: LLMModel(id: "chat")))
        let gate = PhotoLoadGate(started: expectation(description: "First photo loading"))
        defer { gate.release() }
        let first = gate.input("first.png")
        let second = ChatViewModel.ImageInput(fileName: "second.png", loadData: { Data([2]) })
        sut.send(.imagesSelected([first, second]))
        await fulfillment(of: [gate.started], timeout: 2)

        // When
        sut.send(.sendTapped)
        guard case .loaded(let loadingState) = sut.state else { return XCTFail("Expected loaded state") }
        let task = try XCTUnwrap(sut.attachmentPreparationTask)
        gate.release()
        await waitForAttachmentTask(task)

        // Then
        XCTAssertTrue(loadingState.isPreparingAttachment)
        XCTAssertTrue(loadingState.messages.isEmpty)
        XCTAssertEqual(loadingState.inputText, "Compare")
        guard case .loaded(let state) = sut.state else { return XCTFail("Expected loaded state") }
        XCTAssertEqual(state.pendingAttachments.map(\.fileName), ["first.png", "second.png"])
        XCTAssertEqual(state.pendingAttachments.compactMap(\.transientData), [Data([1]), Data([2])])
        XCTAssertFalse(state.isPreparingAttachment)
        XCTAssertTrue(mockAttachmentRepository.savedAttachments.isEmpty)
    }

    func test_send_multipleImages_oneFails_keepsSuccessfulImagesAndReportsFailure() async throws {
        // Given
        sut.state = .loaded(.init(selectedModel: LLMModel(id: "chat")))
        let images = [
            ChatViewModel.ImageInput(fileName: "first.png", loadData: { Data([1]) }),
            ChatViewModel.ImageInput(fileName: "missing.png", loadData: { throw APIError.invalidResponse }),
            ChatViewModel.ImageInput(fileName: "third.png", loadData: { Data([3]) })
        ]

        // When
        sut.send(.imagesSelected(images))
        await waitForAttachmentTask(try XCTUnwrap(sut.attachmentPreparationTask))

        // Then
        guard case .loaded(let state) = sut.state else { return XCTFail("Expected loaded state") }
        XCTAssertEqual(state.pendingAttachments.map(\.fileName), ["first.png", "third.png"])
        XCTAssertNotNil(state.errorMessage)
        XCTAssertFalse(state.isPreparingAttachment)
        sut.errorDismissTask?.cancel()
    }

    func test_send_photoLoadCompletesAfterConversationChange_doesNotAttachToNewConversation() async throws {
        // Given
        sut.state = .loaded(.init(selectedModel: LLMModel(id: "chat")))
        let gate = PhotoLoadGate(started: expectation(description: "Photo loading"))
        defer { gate.release() }
        sut.send(.imagesSelected([gate.input("old.png")]))
        await fulfillment(of: [gate.started], timeout: 2)
        let task = try XCTUnwrap(sut.attachmentPreparationTask)

        // When
        sut.send(.conversationLoaded(Conversation(modelId: "chat")))
        gate.release()
        await waitForAttachmentTask(task)

        // Then
        guard case .loaded(let state) = sut.state else { return XCTFail("Expected loaded state") }
        XCTAssertTrue(state.pendingAttachments.isEmpty)
        XCTAssertFalse(state.isPreparingAttachment)
        XCTAssertNil(state.errorMessage)
    }

    func test_send_reattachStoredOrTransientImage_createsNewIdentityAndPreservesOriginal() async throws {
        for transient in [true, false] {
            // Given
            let bytes = Data([1, 2, 3])
            let image = ChatMessage.Attachment(
                type: .image, fileName: "original.png", mimeType: "image/png", fileRelativePath: "stored.png",
                transientData: transient ? bytes : nil
            )
            let message = ChatMessage(role: .assistant, content: "", attachments: [image])
            mockAttachmentRepository.loadedData = bytes
            sut.state = .loaded(.init(messages: [message], inputText: "Edit", selectedModel: LLMModel(id: "chat")))

            // When
            sut.send(.imageReattached(messageId: message.id, attachmentId: image.id))
            await waitForAttachmentTask(try XCTUnwrap(sut.attachmentPreparationTask))

            // Then
            guard case .loaded(let state) = sut.state else { return XCTFail("Expected loaded state") }
            let pending = try XCTUnwrap(state.pendingAttachments.first)
            XCTAssertNotEqual(pending.id, image.id)
            XCTAssertEqual(pending.transientData, bytes)
            XCTAssertTrue(pending.fileRelativePath.isEmpty)
            XCTAssertEqual(state.messages, [message])
            XCTAssertEqual(state.inputText, "Edit")
            XCTAssertTrue(mockAttachmentRepository.savedAttachments.isEmpty)
        }
    }
}
