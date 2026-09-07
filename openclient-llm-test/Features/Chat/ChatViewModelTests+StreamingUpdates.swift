//
//  ChatViewModelTests+StreamingUpdates.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 20/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

// MARK: - Streaming UI updates

@MainActor
extension ChatViewModelTests {
    func test_enqueueStreamingTextUpdate_burst_buffersUpdatesAfterFirstPublication() {
        // Given
        let assistantId = prepareActiveStream()

        // When
        sut.enqueueStreamingTextUpdate(.token("First"), assistantMessageId: assistantId)
        sut.enqueueStreamingTextUpdate(.token(" second"), assistantMessageId: assistantId)
        sut.enqueueStreamingTextUpdate(.reasoning("Thinking"), assistantMessageId: assistantId)

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.messages.first?.content, "First")
        XCTAssertNil(loadedState.messages.first?.reasoningContent)
        XCTAssertEqual(sut.streamingUpdateBuffer.updates.count, 2)
    }

    func test_flushStreamingTextUpdates_interleavedUpdates_preservesContent() {
        // Given
        let assistantId = prepareActiveStream()
        sut.enqueueStreamingTextUpdate(.token("First"), assistantMessageId: assistantId)
        sut.enqueueStreamingTextUpdate(.reasoning("Think"), assistantMessageId: assistantId)
        sut.enqueueStreamingTextUpdate(.token(" second"), assistantMessageId: assistantId)
        sut.enqueueStreamingTextUpdate(.reasoning(" again"), assistantMessageId: assistantId)

        // When
        sut.flushStreamingTextUpdates(for: assistantId)

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.messages.first?.content, "First second")
        XCTAssertEqual(loadedState.messages.first?.reasoningContent, "Think again")
        XCTAssertEqual(loadedState.streamingRevision, 2)
        XCTAssertTrue(sut.streamingUpdateBuffer.updates.isEmpty)
    }

    func test_enqueueStreamingTextUpdate_emptyReasoning_ignoresUpdate() {
        // Given
        let assistantId = prepareActiveStream()
        sut.enqueueStreamingTextUpdate(.token("Answer"), assistantMessageId: assistantId)

        // When
        let didPublish = sut.enqueueStreamingTextUpdate(.reasoning(""), assistantMessageId: assistantId)

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertFalse(didPublish)
        XCTAssertNil(loadedState.messages.first?.reasoningContent)
        XCTAssertTrue(sut.streamingUpdateBuffer.updates.isEmpty)
    }

    func test_enqueueStreamingTextUpdate_largeBurst_remainsBufferedUntilScheduledFlush() {
        // Given
        let assistantId = prepareActiveStream()
        sut.enqueueStreamingTextUpdate(.token("First"), assistantMessageId: assistantId)
        let bufferedText = String(repeating: "a", count: 1_024)

        // When
        let didPublish = sut.enqueueStreamingTextUpdate(.token(bufferedText), assistantMessageId: assistantId)

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertFalse(didPublish)
        XCTAssertEqual(loadedState.messages.first?.content, "First")
        XCTAssertEqual(sut.streamingUpdateBuffer.updates.count, 1)
    }

    func test_cancelActiveStreaming_withBufferedText_flushesPartialResponse() {
        // Given
        let assistantId = prepareActiveStream()
        sut.beginStreamingBackground(for: assistantId)
        sut.enqueueStreamingTextUpdate(.token("First"), assistantMessageId: assistantId)
        sut.enqueueStreamingTextUpdate(.token(" second"), assistantMessageId: assistantId)

        // When
        sut.cancelActiveStreaming(shouldPersist: false)

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.messages.first?.content, "First second")
        XCTAssertFalse(loadedState.isStreaming)
        XCTAssertNil(sut.streamingUpdateBuffer.assistantMessageId)
        XCTAssertEqual(mockStreamingBackground.completionResults, [false])
        XCTAssertNil(sut.backgroundPersistenceCheckpointTask)
        XCTAssertNil(sut.backgroundPersistenceObserver)
    }

    func test_enqueueStreamingTextUpdate_staleAssistant_doesNotMutateCurrentStream() {
        // Given
        let assistantId = prepareActiveStream()

        // When
        sut.enqueueStreamingTextUpdate(.token("Ignored"), assistantMessageId: UUID())

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.messages.first?.id, assistantId)
        XCTAssertEqual(loadedState.messages.first?.content, "")
        XCTAssertNil(sut.streamingUpdateBuffer.assistantMessageId)
    }

    func test_send_sendTapped_streamCompletes_tracksBackgroundLifecycle() async {
        // Given
        let model = LLMModel(id: "gpt-4")
        sut.state = .loaded(sut.makeLoadedState(models: [model], pending: nil))
        mockStreamMessage.chunks = [.reasoning("Working"), .token("Answer")]
        let completed = expectation(description: "Background task completed")
        mockStreamingBackground.onEnd = { _ in completed.fulfill() }
        sut.send(.inputChanged("Question"))

        // When
        sut.send(.sendTapped)
        await fulfillment(of: [completed], timeout: 1)

        // Then
        XCTAssertEqual(mockStreamingBackground.beginCallCount, 1)
        XCTAssertTrue(mockStreamingBackground.phases.contains(.thinking))
        XCTAssertTrue(mockStreamingBackground.phases.contains(.responding))
        XCTAssertEqual(mockStreamingBackground.phases.last, .saving)
        XCTAssertEqual(mockStreamingBackground.completionResults, [true])
        XCTAssertEqual(mockNotifyStreamingCompleted.completionCallCount, 1)
        XCTAssertNil(sut.backgroundPersistenceCheckpointTask)
        XCTAssertNil(sut.backgroundPersistenceObserver)
        XCTAssertNil(sut.activeAssistantMessageId)
        XCTAssertNil(sut.streamTask)
    }

    func test_send_sendTapped_continuedTaskCompletes_doesNotNotify() async {
        // Given
        let model = LLMModel(id: "gpt-4")
        sut.state = .loaded(sut.makeLoadedState(models: [model], pending: nil))
        mockStreamMessage.chunks = [.token("Answer")]
        mockStreamingBackground.shouldSendCompletionNotification = false
        let completed = expectation(description: "Background task completed")
        mockStreamingBackground.onEnd = { _ in completed.fulfill() }
        sut.send(.inputChanged("Question"))

        // When
        sut.send(.sendTapped)
        await fulfillment(of: [completed], timeout: 1)

        // Then
        XCTAssertEqual(mockStreamingBackground.completionResults, [true])
        XCTAssertEqual(mockNotifyStreamingCompleted.completionCallCount, 0)
    }

    func test_send_sendTapped_persistenceFails_completesBackgroundTaskAsFailure() async {
        // Given
        let model = LLMModel(id: "gpt-4")
        sut.state = .loaded(sut.makeLoadedState(models: [model], pending: nil))
        mockStreamMessage.chunks = [.token("Answer")]
        mockSaveConversation.error = NSError(domain: "test", code: 1)
        let completed = expectation(description: "Background task completed")
        mockStreamingBackground.onEnd = { _ in completed.fulfill() }
        sut.send(.inputChanged("Question"))

        // When
        sut.send(.sendTapped)
        await fulfillment(of: [completed], timeout: 1)

        // Then
        XCTAssertGreaterThanOrEqual(mockSaveConversation.executeCallCount, 1)
        XCTAssertEqual(mockStreamingBackground.completionResults, [false])
        XCTAssertEqual(mockNotifyStreamingCompleted.completionCallCount, 0)
        XCTAssertNil(sut.activeAssistantMessageId)
        XCTAssertNil(sut.streamTask)
        XCTAssertNil(sut.backgroundPersistenceCheckpointTask)
        XCTAssertNil(sut.backgroundPersistenceObserver)
    }

    func test_beginStreamingBackground_expiration_stopsActiveResponse() async {
        // Given
        let assistantId = prepareActiveStream()
        sut.beginStreamingBackground(for: assistantId)

        // When
        mockStreamingBackground.expire()

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertFalse(loadedState.isStreaming)
        XCTAssertNil(sut.activeAssistantMessageId)
        XCTAssertEqual(mockNotifyStreamingCompleted.expirationCallCount, 1)
        XCTAssertNil(sut.backgroundPersistenceCheckpointTask)
        XCTAssertNil(sut.backgroundPersistenceObserver)
    }

    private func prepareActiveStream() -> UUID {
        let assistantId = UUID()
        var loadedState = ChatViewModel.LoadedState()
        loadedState.messages = [ChatMessage(id: assistantId, role: .assistant, content: "")]
        loadedState.isStreaming = true
        sut.state = .loaded(loadedState)
        sut.activeAssistantMessageId = assistantId
        return assistantId
    }
}
