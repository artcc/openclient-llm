//
//  ChatViewModelTests+AppHandoff.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 29/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

// MARK: - Tests — App handoff

@MainActor
extension ChatViewModelTests {
    func test_prepareForAppHandoff_withoutConversation_returnsNewChat() async {
        // Given
        sut.state = .loaded(.init())

        // When
        let result = await sut.prepareForAppHandoff()

        // Then
        XCTAssertEqual(result, .newChat)
        XCTAssertEqual(mockSaveConversation.executeCallCount, 0)
    }

    func test_prepareForAppHandoff_withConversation_persistsAndReturnsConversation() async {
        // Given
        let conversation = Conversation(modelId: "gpt-4")
        let messages = [ChatMessage(role: .user, content: "Hello")]
        sut.state = .loaded(.init(conversation: conversation, messages: messages))

        // When
        let result = await sut.prepareForAppHandoff()

        // Then
        guard case .conversation(let handedOffConversation) = result else {
            return XCTFail("Expected conversation handoff")
        }
        XCTAssertEqual(handedOffConversation.id, conversation.id)
        XCTAssertEqual(handedOffConversation.messages, messages)
        XCTAssertEqual(mockSaveConversation.executeCallCount, 1)
        XCTAssertEqual(mockSaveConversation.savedConversations.first?.messages, messages)
    }

    func test_prepareForAppHandoff_withDraft_returnsDraftPendingWithoutSaving() async {
        // Given
        let conversation = Conversation(modelId: "gpt-4")
        sut.state = .loaded(.init(conversation: conversation, inputText: "Unsent draft"))

        // When
        let result = await sut.prepareForAppHandoff()

        // Then
        XCTAssertEqual(result, .draftPending)
        XCTAssertEqual(mockSaveConversation.executeCallCount, 0)
    }

    func test_canPrepareForAppHandoff_withPendingOperations_returnsFalse() {
        // Given
        let attachment = ChatMessage.Attachment(
            type: .pdf,
            fileName: "document.pdf",
            mimeType: "application/pdf",
            fileRelativePath: "",
            transientData: Data()
        )
        let blockedStates = [
            ChatViewModel.LoadedState(pendingAttachments: [attachment]),
            ChatViewModel.LoadedState(isPreparingAttachment: true),
            ChatViewModel.LoadedState(isRecording: true),
            ChatViewModel.LoadedState(isStartingRecording: true),
            ChatViewModel.LoadedState(isTranscribing: true)
        ]

        // When / Then
        for state in blockedStates {
            sut.state = .loaded(state)
            XCTAssertFalse(sut.canPrepareForAppHandoff)
        }
    }

    func test_prepareForAppHandoff_persistenceFails_returnsFailureAndSetsError() async {
        // Given
        let conversation = Conversation(modelId: "gpt-4")
        mockSaveConversation.error = APIError.invalidResponse
        sut.state = .loaded(.init(conversation: conversation))

        // When
        let result = await sut.prepareForAppHandoff()

        // Then
        XCTAssertEqual(result, .persistenceFailed)
        guard case .loaded(let loadedState) = sut.state else {
            return XCTFail("Expected loaded state")
        }
        XCTAssertNotNil(loadedState.errorMessage)
    }

    func test_prepareForAppHandoff_whilePersistenceRuns_ignoresNewInput() async {
        // Given
        let conversation = Conversation(modelId: "gpt-4")
        let saveStarted = expectation(description: "Handoff persistence started")
        var resumeSave: CheckedContinuation<Void, Never>?
        mockSaveConversation.asyncExecuteHandler = { submitted, _, _ in
            saveStarted.fulfill()
            await withCheckedContinuation { resumeSave = $0 }
            return submitted
        }
        sut.state = .loaded(.init(conversation: conversation))
        let handoffTask = Task { await self.sut.prepareForAppHandoff() }
        await fulfillment(of: [saveStarted], timeout: 1)

        // When
        sut.send(.inputChanged("Late mutation"))
        resumeSave?.resume()
        let result = await handoffTask.value

        // Then
        guard case .conversation(let handedOffConversation) = result,
              case .loaded(let loadedState) = sut.state else {
            return XCTFail("Expected completed conversation handoff")
        }
        XCTAssertEqual(handedOffConversation.id, conversation.id)
        XCTAssertTrue(loadedState.inputText.isEmpty)
    }

    func test_prepareForAppHandoff_emptyStreamingAssistant_removesPlaceholderBeforeSaving() async {
        // Given
        let assistantMessage = ChatMessage(role: .assistant, content: "")
        let userMessage = ChatMessage(role: .user, content: "Hello")
        let conversation = Conversation(modelId: "gpt-4")
        sut.state = .loaded(.init(
            conversation: conversation,
            messages: [userMessage, assistantMessage],
            isStreaming: true
        ))
        sut.activeAssistantMessageId = assistantMessage.id

        // When
        let result = await sut.prepareForAppHandoff()

        // Then
        guard case .conversation(let handedOffConversation) = result else {
            return XCTFail("Expected conversation handoff")
        }
        XCTAssertEqual(handedOffConversation.messages, [userMessage])
        XCTAssertEqual(mockSaveConversation.savedConversations.first?.messages, [userMessage])
    }
}
