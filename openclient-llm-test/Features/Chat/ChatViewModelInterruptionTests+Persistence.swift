//
//  ChatViewModelInterruptionTests+Persistence.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 21/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

extension ChatViewModelInterruptionTests {
    func test_expiration_completedResponseAwaitingSave_doesNotMarkOrNotifyInterruption() async throws {
        // Given
        makeViewModel()
        let gate = TestAsyncGate()
        defer { Task { await gate.open() } }
        let saving = expectation(description: "Saving completed response")
        save.asyncExecuteHandler = { conversation, _, call in
            if call == 1 {
                saving.fulfill()
                await gate.wait()
            }
            return conversation
        }
        let task = try await startResponse()
        let continuation = try XCTUnwrap(stream.continuations.last)
        continuation.yield(.token("Complete answer"))
        continuation.finish()
        await fulfillment(of: [saving], timeout: 1)
        XCTAssertFalse(try loadedState().isStreaming)
        XCTAssertNotNil(sut.activeAssistantMessageId)

        // When
        background.expire()
        await gate.open()
        await task.value
        _ = await sut.persistenceTask?.value

        // Then
        XCTAssertEqual(try loadedState().messages.last?.content, "Complete answer")
        XCTAssertNil(try loadedState().messages.last?.responseInterruption)
        XCTAssertNil(save.savedConversations.last?.messages.last?.responseInterruption)
        XCTAssertEqual(notifications.expirationCallCount, 0)
    }

    func test_expiration_failureAwaitingSave_preservesOriginalError() async throws {
        // Given
        makeViewModel()
        let gate = TestAsyncGate()
        defer { Task { await gate.open() } }
        let saving = expectation(description: "Saving failed response")
        save.asyncExecuteHandler = { conversation, _, call in
            if call == 1 {
                saving.fulfill()
                await gate.wait()
            }
            return conversation
        }
        let task = try await startResponse()
        let continuation = try XCTUnwrap(stream.continuations.last)
        continuation.yield(.token("Partial"))
        continuation.finish(throwing: APIError.serverUnreachable)
        await fulfillment(of: [saving], timeout: 1)
        let originalError = try loadedState().errorMessage

        // When
        background.expire()
        await gate.open()
        await task.value
        _ = await sut.persistenceTask?.value

        // Then
        XCTAssertNotNil(originalError)
        XCTAssertEqual(try loadedState().errorMessage, originalError)
        XCTAssertNil(try loadedState().messages.last?.responseInterruption)
        XCTAssertEqual(notifications.expirationCallCount, 0)
    }

    func test_expiration_previousCheckpointPending_preservesNewStatusAfterReconciliation() async throws {
        // Given
        makeViewModel()
        let gate = TestAsyncGate()
        defer { Task { await gate.open() } }
        let saving = expectation(description: "Checkpoint pending")
        save.asyncExecuteHandler = { conversation, _, call in
            if call == 1 {
                saving.fulfill()
                await gate.wait()
            }
            return conversation
        }
        let task = try await startResponse()
        let id = try XCTUnwrap(sut.activeAssistantMessageId)
        sut.enqueueStreamingTextUpdate(.token("Partial"), assistantMessageId: id)
        sut.scheduleConversationPersistence()
        await fulfillment(of: [saving], timeout: 1)

        // When
        background.expire()
        let finalPersistence = sut.persistenceTask
        await gate.open()
        await task.value
        _ = await finalPersistence?.value

        // Then
        XCTAssertEqual(save.savedConversations.count, 2)
        XCTAssertNil(save.savedConversations.first?.messages.last?.responseInterruption)
        XCTAssertEqual(save.savedConversations.last?.messages.last?.responseInterruption, .backgroundTaskEnded)
        XCTAssertEqual(try loadedState().messages.last?.responseInterruption, .backgroundTaskEnded)
        XCTAssertEqual(try loadedState().messages.last?.content, "Partial")
    }

    func test_retry_oldSaveFinishes_doesNotRestoreOldPlaceholder() async throws {
        // Given
        makeViewModel()
        let gate = TestAsyncGate()
        defer { Task { await gate.open() } }
        let saving = expectation(description: "Interrupted response save pending")
        save.asyncExecuteHandler = { conversation, _, call in
            if call == 1 {
                saving.fulfill()
                await gate.wait()
            }
            return conversation
        }
        let oldTask = try await startResponse()
        let oldId = try XCTUnwrap(sut.activeAssistantMessageId)
        background.expire()
        await oldTask.value
        await fulfillment(of: [saving], timeout: 1)
        let pendingSave = sut.persistenceTask
        let restarted = expectation(description: "Retry started")
        stream.onExecute = { restarted.fulfill() }

        // When
        sut.send(.retryInterruptedResponse(oldId))
        let newTask = try XCTUnwrap(sut.streamTask)
        await fulfillment(of: [restarted], timeout: 1)
        let newId = sut.activeAssistantMessageId
        await gate.open()
        _ = await pendingSave?.value

        // Then
        XCTAssertNotEqual(oldId, newId)
        XCTAssertEqual(try loadedState().messages.last?.id, newId)
        XCTAssertFalse(try loadedState().messages.contains { $0.id == oldId })
        XCTAssertNil(try loadedState().messages.last?.responseInterruption)
        sut.send(.stopStreamingTapped)
        await newTask.value
    }

    func test_expiration_saveFails_keepsVisibleStatusInMemory() async throws {
        // Given
        makeViewModel()
        save.error = APIError.invalidResponse
        let task = try await startResponse()

        // When
        background.expire()
        await task.value
        let result = await sut.persistenceTask?.value

        // Then
        XCTAssertTrue(try loadedState().messages.last?.isInterruptedResponse == true)
        XCTAssertNotEqual(result?.didPersist, true)
        XCTAssertNil(sut.activeAssistantMessageId)
    }

    func test_expiration_oldCallbackAfterConversationChange_doesNotMutateNewConversation() async throws {
        // Given
        makeViewModel()
        let task = try await startResponse()
        let callback = background.expirationHandler
        let next = Conversation(modelId: "test", messages: [ChatMessage(role: .user, content: "Different chat")])

        // When
        sut.send(.conversationLoaded(next))
        callback?()
        await task.value
        _ = await sut.persistenceTask?.value

        // Then
        XCTAssertEqual(try loadedState().conversation?.id, next.id)
        XCTAssertEqual(try loadedState().messages, next.messages)
        XCTAssertEqual(notifications.expirationCallCount, 0)
    }
}
