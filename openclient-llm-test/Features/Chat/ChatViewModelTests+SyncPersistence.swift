//
//  ChatViewModelTests+SyncPersistence.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 11/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

// MARK: - Synchronization Persistence

@MainActor
extension ChatViewModelTests {
    func test_send_sendTapped_newConversationUsesNilPersistenceBase() async throws {
        // Given
        mockFetchModels.result = .success([LLMModel(id: "gpt-4")])
        mockStreamMessage.chunks = [.token("Response")]
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))
        sut.send(.inputChanged("Hello"))

        // When
        sut.send(.sendTapped)
        await waitUntil { !self.mockSaveConversation.expectedBases.isEmpty }

        // Then
        XCTAssertNil(mockSaveConversation.expectedBases[0])
    }

    func test_send_systemPromptChanged_persistsAgainstDurableConversationBase() async throws {
        // Given
        mockFetchModels.result = .success([LLMModel(id: "gpt-4")])
        let conversation = Conversation(modelId: "gpt-4", systemPrompt: "Original")
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))
        sut.send(.conversationLoaded(conversation))

        // When
        sut.send(.systemPromptChanged("Updated"))
        await waitUntil { !self.mockSaveConversation.savedConversations.isEmpty }

        // Then
        XCTAssertEqual((mockSaveConversation.expectedBases.last ?? nil)?.systemPrompt, "Original")
        XCTAssertEqual(mockSaveConversation.savedConversations.last?.systemPrompt, "Updated")
    }

    func test_send_sendTapped_pendingAttachmentUsesCreatedConversationFolder() async throws {
        // Given
        mockFetchModels.result = .success([LLMModel(id: "gpt-4")])
        mockStreamMessage.chunks = [.token("Response")]
        mockSaveConversation.executeHandler = { conversation, _ in
            var persisted = conversation
            for messageIndex in persisted.messages.indices {
                for attachmentIndex in persisted.messages[messageIndex].attachments.indices {
                    let attachment = persisted.messages[messageIndex].attachments[attachmentIndex]
                    persisted.messages[messageIndex].attachments[attachmentIndex] = ChatMessage.Attachment(
                        id: attachment.id,
                        type: attachment.type,
                        fileName: attachment.fileName,
                        mimeType: attachment.mimeType,
                        fileRelativePath: ConversationAttachmentPath.relativePath(
                            for: attachment,
                            conversationId: conversation.id
                        )
                    )
                }
            }
            return persisted
        }
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))
        sut.send(.attachmentAdded(data: Data([0xFF, 0xD8]), fileName: "test.jpg", type: .image))
        try await Task.sleep(for: .milliseconds(50))
        sut.send(.inputChanged("Describe"))

        // When
        sut.send(.sendTapped)
        await waitUntil {
            self.sut.persistenceBase?.messages.first?.attachments.first?.fileRelativePath.isEmpty == false
        }

        // Then
        let submitted = try XCTUnwrap(mockSaveConversation.savedConversations.last)
        XCTAssertEqual(submitted.messages.first?.attachments.first?.transientData, Data([0xFF, 0xD8]))
        let conversation = try XCTUnwrap(sut.persistenceBase)
        let attachment = try XCTUnwrap(conversation.messages.first?.attachments.first)
        XCTAssertTrue(attachment.fileRelativePath.contains(conversation.id.uuidString))
        XCTAssertNil(attachment.transientData)
    }

    func test_persistence_previousSaveFails_nextSaveUsesLastDurableBase() async throws {
        // Given
        mockFetchModels.result = .success([LLMModel(id: "gpt-4")])
        let conversation = Conversation(modelId: "gpt-4", systemPrompt: "Original")
        mockSaveConversation.failureAtCall = 1
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))
        sut.send(.conversationLoaded(conversation))

        // When
        sut.send(.systemPromptChanged("First"))
        sut.send(.systemPromptChanged("Second"))
        await waitUntil { self.mockSaveConversation.executeCallCount == 2 }

        // Then
        XCTAssertEqual((mockSaveConversation.expectedBases.last ?? nil)?.systemPrompt, "Original")
        XCTAssertEqual(mockSaveConversation.savedConversations.last?.systemPrompt, "Second")
    }

    func test_persistence_reconciledResult_updatesVisibleHistoryAndDurableBase() async throws {
        // Given
        mockFetchModels.result = .success([LLMModel(id: "gpt-4")])
        let initial = ChatMessage(role: .user, content: "Initial")
        let conversation = Conversation(modelId: "gpt-4", messages: [initial])
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))
        sut.send(.conversationLoaded(conversation))
        guard case .loaded(var loadedState) = sut.state else {
            return XCTFail("Expected loaded state")
        }
        let local = ChatMessage(role: .assistant, content: "Local")
        loadedState.messages.append(local)
        sut.state = .loaded(loadedState)
        var reconciled = conversation
        reconciled.messages = [
            initial,
            ChatMessage(role: .assistant, content: "Remote"),
            local
        ]
        reconciled.updatedAt = Date()
        mockSaveConversation.result = reconciled

        // When
        let didPersist = await sut.persistConversation()

        // Then
        XCTAssertTrue(didPersist)
        guard case .loaded(let finalState) = sut.state else {
            return XCTFail("Expected loaded state")
        }
        XCTAssertEqual(finalState.messages.map(\.content), ["Initial", "Remote", "Local"])
        XCTAssertEqual(sut.persistenceBase, reconciled)
    }

    func test_persistence_queuedRevision_rebasesOntoDurableResult() async throws {
        // Given
        let gate = TestAsyncGate()
        let firstSaveStarted = expectation(description: "First save started")
        let remoteMessage = ChatMessage(role: .assistant, content: "Remote")
        let attachment = ChatMessage.Attachment(
            type: .image, fileName: "generated.png", mimeType: "image/png",
            fileRelativePath: "", transientData: Data([0x01, 0x02])
        )
        let assistantId = UUID()
        let conversation = Conversation(modelId: "gpt-4", messages: [ChatMessage(role: .user, content: "Initial")])
        configureQueuedPersistence(
            gate: gate, firstSaveStarted: firstSaveStarted, remoteMessage: remoteMessage, assistantId: assistantId
        )
        var firstState = sut.makeLoadedState(models: [LLMModel(id: "gpt-4")], pending: conversation)
        firstState.messages.append(ChatMessage(
            id: assistantId,
            role: .assistant,
            content: "Partial",
            attachments: [attachment]
        ))
        sut.state = .loaded(firstState)
        sut.scheduleConversationPersistence()
        await fulfillment(of: [firstSaveStarted], timeout: 2)
        guard mockSaveConversation.executeCallCount == 1 else {
            await gate.open()
            return XCTFail("Expected first save to be waiting")
        }
        guard case .loaded(var finalState) = sut.state,
              let assistantIndex = finalState.messages.firstIndex(where: { $0.id == assistantId }) else {
            await gate.open()
            return XCTFail("Expected assistant message")
        }
        finalState.messages[assistantIndex].content = "Final"
        sut.state = .loaded(finalState)

        // When
        let queuedPersistence = sut.scheduleConversationPersistence()
        await gate.open()
        let persistenceTask = try XCTUnwrap(queuedPersistence)
        let result = await persistenceTask.value

        // Then
        XCTAssertTrue(result.didPersist)
        XCTAssertEqual(mockSaveConversation.executeCallCount, 2)
        guard mockSaveConversation.expectedBases.count == 2,
              mockSaveConversation.savedConversations.count == 2 else {
            return XCTFail("Expected both persistence submissions")
        }
        let durableBase = try XCTUnwrap(mockSaveConversation.expectedBases[1])
        let finalSubmission = mockSaveConversation.savedConversations[1]
        XCTAssertTrue(durableBase.messages.contains(where: { $0.id == remoteMessage.id }))
        XCTAssertTrue(finalSubmission.messages.contains(where: { $0.id == remoteMessage.id }))
        let savedAssistant = try XCTUnwrap(finalSubmission.messages.first(where: { $0.id == assistantId }))
        XCTAssertEqual(savedAssistant.content, "Final")
        XCTAssertEqual(savedAssistant.attachments.first?.transientData, Data([0x01, 0x02]))
    }

    func test_resetAfterAppDataReset_streamingConversation_doesNotQueuePersistence() async {
        // Given
        let gate = TestAsyncGate()
        let conversation = Conversation(modelId: "gpt-4", messages: [ChatMessage(role: .user, content: "Hello")])
        mockSaveConversation.asyncExecuteHandler = { submitted, _, _ in
            await gate.wait()
            return submitted
        }
        var loadedState = sut.makeLoadedState(models: [LLMModel(id: "gpt-4")], pending: conversation)
        loadedState.isStreaming = true
        sut.state = .loaded(loadedState)
        sut.scheduleConversationPersistence()
        await waitUntil { self.mockSaveConversation.executeCallCount == 1 }
        let pendingPersistence = sut.persistenceTask

        // When
        sut.resetAfterAppDataReset()
        await gate.open()
        _ = await pendingPersistence?.value

        // Then
        XCTAssertEqual(mockSaveConversation.executeCallCount, 1)
        XCTAssertNil(sut.persistenceTask)
        XCTAssertNil(sut.queuedPersistenceConversation)
        XCTAssertNil(sut.persistenceBase)
    }
}

// MARK: - Private

private extension ChatViewModelTests {
    func configureQueuedPersistence(
        gate: TestAsyncGate,
        firstSaveStarted: XCTestExpectation,
        remoteMessage: ChatMessage,
        assistantId: UUID
    ) {
        mockSaveConversation.asyncExecuteHandler = { submitted, _, call in
            guard call == 1 else { return submitted }
            firstSaveStarted.fulfill()
            await gate.wait()
            var persisted = submitted
            persisted.messages.insert(remoteMessage, at: 1)
            if let index = persisted.messages.firstIndex(where: { $0.id == assistantId }) {
                persisted.messages[index].attachments = persisted.messages[index].attachments.map { attachment in
                    ChatMessage.Attachment(
                        id: attachment.id,
                        type: attachment.type,
                        fileName: attachment.fileName,
                        mimeType: attachment.mimeType,
                        fileRelativePath: "Attachments/generated.png"
                    )
                }
            }
            return persisted
        }
    }
}
