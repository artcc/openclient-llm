//
//  ChatViewModelTests+PrivateChat.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 13/07/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

// MARK: - Tests - Private Chat

@MainActor
extension ChatViewModelTests {
    func test_send_attachmentAdded_inPrivateChat_keepsDataInMemory() async throws {
        // Given
        let data = Data([0xFF, 0xD8])
        sut = ChatViewModel(
            isPrivateChat: true,
            state: .loaded(.init()),
            prepareImageAttachmentUseCase: mockPrepareImageAttachment,
            attachmentRepository: mockAttachmentRepository,
            saveConversationUseCase: mockSaveConversation
        )

        // When
        sut.send(.attachmentAdded(data: data, fileName: "private.jpg", type: .image))
        try await Task.sleep(for: .milliseconds(50))

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.pendingAttachments.first?.transientData, data)
        XCTAssertTrue(mockAttachmentRepository.savedAttachments.isEmpty)
    }

    func test_send_sendTapped_inPrivateChat_doesNotCreateOrSaveConversation() {
        // Given
        let model = LLMModel(id: "gpt-4")
        sut = ChatViewModel(
            initialFolderID: UUID(),
            isPrivateChat: true,
            state: .loaded(.init(selectedModel: model)),
            streamMessageUseCase: mockStreamMessage,
            saveConversationUseCase: mockSaveConversation,
            streamingBackgroundUseCase: mockStreamingBackground,
            notifyStreamingCompletedUseCase: mockNotifyStreamingCompleted
        )
        sut.send(.inputChanged("Keep this private"))

        // When
        sut.send(.sendTapped)

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertNil(loadedState.conversation)
        XCTAssertEqual(mockSaveConversation.executeCallCount, 0)
    }
}
