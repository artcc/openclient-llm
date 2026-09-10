//
//  BranchConversationUseCaseTests.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 03/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class BranchConversationUseCaseTests: XCTestCase {
    // MARK: - Properties

    var sut: BranchConversationUseCase!
    var mockSave: MockSaveConversationUseCase!
    var mockAttachments: MockAttachmentRepository!

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()
        mockSave = MockSaveConversationUseCase()
        mockAttachments = MockAttachmentRepository()
        sut = BranchConversationUseCase(
            saveConversationUseCase: mockSave,
            attachmentRepository: mockAttachments
        )
    }

    override func tearDown() async throws {
        sut = nil
        mockSave = nil
        mockAttachments = nil
        try await super.tearDown()
    }

    // MARK: - Tests

    func test_execute_userAttemptWithoutTranscript_preservesReservationWithNewMessageId() async throws {
        // Given
        let user = ChatMessage(role: .user, content: "Draw a cat", imageGenerationAttempted: true)
        let conversation = Conversation(modelId: "principal", messages: [user])

        // When
        let fork = try await sut.execute(conversation: conversation, fromMessageId: user.id)

        // Then
        XCTAssertEqual(fork.messages.first?.imageGenerationAttempted, true)
        XCTAssertNotEqual(fork.messages.first?.id, user.id)
        XCTAssertEqual(mockSave.savedConversations.last?.messages.first?.imageGenerationAttempted, true)
    }

    func test_execute_createsNewConversationWithMessagesUpToAndIncludingTarget() async throws {
        // Given
        let msg1 = ChatMessage(role: .user, content: "First")
        let msg2 = ChatMessage(role: .assistant, content: "Second")
        let msg3 = ChatMessage(role: .user, content: "Third")
        let conversation = Conversation(modelId: "gpt-4", messages: [msg1, msg2, msg3])

        // When — fork from msg2 (assistant)
        let fork = try await sut.execute(conversation: conversation, fromMessageId: msg2.id)

        // Then
        XCTAssertEqual(fork.messages.count, 2)
        XCTAssertEqual(fork.messages.first?.content, "First")
        XCTAssertEqual(fork.messages.last?.content, "Second")
    }

    func test_execute_setsParentConversationId() async throws {
        // Given
        let msg = ChatMessage(role: .user, content: "Hello")
        let conversation = Conversation(modelId: "gpt-4", messages: [msg])

        // When
        let fork = try await sut.execute(conversation: conversation, fromMessageId: msg.id)

        // Then
        XCTAssertEqual(fork.parentConversationId, conversation.id)
    }

    func test_execute_setsBranchedFromMessageId() async throws {
        // Given
        let msg = ChatMessage(role: .user, content: "Hello")
        let conversation = Conversation(modelId: "gpt-4", messages: [msg])

        // When
        let fork = try await sut.execute(conversation: conversation, fromMessageId: msg.id)

        // Then
        XCTAssertEqual(fork.branchedFromMessageId, msg.id)
    }

    func test_execute_preservesModelAndSystemPrompt() async throws {
        // Given
        let msg = ChatMessage(role: .user, content: "Hello")
        let conversation = Conversation(
            modelId: "llama3",
            systemPrompt: "Be concise",
            messages: [msg]
        )

        // When
        let fork = try await sut.execute(conversation: conversation, fromMessageId: msg.id)

        // Then
        XCTAssertEqual(fork.modelId, "llama3")
        XCTAssertEqual(fork.systemPrompt, "Be concise")
    }

    func test_execute_forkSavedToPersistence() async throws {
        // Given
        let msg = ChatMessage(role: .user, content: "Hello")
        let conversation = Conversation(modelId: "gpt-4", messages: [msg])

        // When
        _ = try await sut.execute(conversation: conversation, fromMessageId: msg.id)

        // Then
        XCTAssertFalse(mockSave.savedConversations.isEmpty)
    }

    func test_execute_forkHasUniqueId() async throws {
        // Given
        let msg = ChatMessage(role: .user, content: "Hello")
        let conversation = Conversation(modelId: "gpt-4", messages: [msg])

        // When
        let fork = try await sut.execute(conversation: conversation, fromMessageId: msg.id)

        // Then
        XCTAssertNotEqual(fork.id, conversation.id)
    }

    func test_execute_forkMessagesHaveUniqueIdsAndRemappedSummaryCursor() async throws {
        // Given
        let first = ChatMessage(role: .user, content: "First")
        let second = ChatMessage(role: .assistant, content: "Second")
        let conversation = Conversation(
            modelId: "gpt-4",
            contextSummary: "First exchange",
            contextSummaryCursorMessageId: first.id,
            messages: [first, second]
        )

        // When
        let fork = try await sut.execute(conversation: conversation, fromMessageId: second.id)

        // Then
        XCTAssertTrue(Set(fork.messages.map(\.id)).isDisjoint(with: Set(conversation.messages.map(\.id))))
        XCTAssertEqual(fork.contextSummaryCursorMessageId, fork.messages.first?.id)
        XCTAssertEqual(fork.branchedFromMessageId, second.id)
    }

    func test_execute_withUnknownMessageId_throwsError() async {
        // Given
        let msg = ChatMessage(role: .user, content: "Hello")
        let conversation = Conversation(modelId: "gpt-4", messages: [msg])
        let unknownId = UUID()

        // When / Then
        do {
            _ = try await sut.execute(conversation: conversation, fromMessageId: unknownId)
            XCTFail("Expected message-not-found error")
        } catch {
            XCTAssertEqual(error as? BranchConversationError, .messageNotFound)
        }
    }

    func test_execute_forkFromLastMessage_includesAllMessages() async throws {
        // Given
        let messages = (1...5).map { idx in
            ChatMessage(role: idx % 2 != 0 ? .user : .assistant, content: "Message \(idx)")
        }
        let conversation = Conversation(modelId: "gpt-4", messages: messages)
        let lastId = try XCTUnwrap(messages.last).id

        // When
        let fork = try await sut.execute(conversation: conversation, fromMessageId: lastId)

        // Then
        XCTAssertEqual(fork.messages.count, 5)
    }

    func test_execute_forkFromFirstMessage_includesOnlyFirstMessage() async throws {
        // Given
        let messages = [
            ChatMessage(role: .user, content: "First"),
            ChatMessage(role: .assistant, content: "Second"),
            ChatMessage(role: .user, content: "Third")
        ]
        let conversation = Conversation(modelId: "gpt-4", messages: messages)
        let firstId = try XCTUnwrap(messages.first).id

        // When
        let fork = try await sut.execute(conversation: conversation, fromMessageId: firstId)

        // Then
        XCTAssertEqual(fork.messages.count, 1)
        XCTAssertEqual(fork.messages.first?.content, "First")
    }

    func test_execute_beforeSummaryCursor_doesNotLeakFutureSummary() async throws {
        // Given
        let first = ChatMessage(role: .user, content: "First")
        let summarized = ChatMessage(role: .assistant, content: "Summarized")
        let conversation = Conversation(
            modelId: "gpt-4",
            contextSummary: "Includes future context",
            contextSummaryCursorMessageId: summarized.id,
            messages: [first, summarized]
        )

        // When
        let fork = try await sut.execute(conversation: conversation, fromMessageId: first.id)

        // Then
        XCTAssertNil(fork.contextSummary)
    }

    func test_execute_withAttachment_stagesBytesForAtomicPersistence() async throws {
        // Given
        let parentId = UUID()
        let bytes = Data([0x01, 0x02, 0x03])
        let attachment = ChatMessage.Attachment(
            type: .image,
            fileName: "image.png",
            mimeType: "image/png",
            fileRelativePath: "Attachments/\(parentId.uuidString)/image.png"
        )
        let message = ChatMessage(role: .user, content: "Image", attachments: [attachment])
        let conversation = Conversation(id: parentId, modelId: "model", messages: [message])
        mockAttachments.loadedData = bytes

        // When
        let fork = try await sut.execute(conversation: conversation, fromMessageId: message.id)

        // Then
        let copiedAttachment = try XCTUnwrap(fork.messages.first?.attachments.first)
        XCTAssertEqual(copiedAttachment.transientData, bytes)
        XCTAssertTrue(copiedAttachment.fileRelativePath.isEmpty)
        XCTAssertTrue(mockAttachments.savedAttachments.isEmpty)
    }

    func test_execute_saveFails_leavesNoStagedAttachmentFolder() async {
        // Given
        let parentId = UUID()
        let attachment = ChatMessage.Attachment(
            type: .image,
            fileName: "image.png",
            mimeType: "image/png",
            fileRelativePath: "Attachments/\(parentId.uuidString)/image.png"
        )
        let message = ChatMessage(role: .user, content: "Image", attachments: [attachment])
        let conversation = Conversation(id: parentId, modelId: "model", messages: [message])
        mockAttachments.loadedData = Data([0x01])
        mockSave.error = NSError(domain: "test", code: 1)

        // When
        do {
            _ = try await sut.execute(conversation: conversation, fromMessageId: message.id)
            XCTFail("Expected save to fail")
        } catch {
            // Then
            XCTAssertTrue(mockAttachments.savedAttachments.isEmpty)
            XCTAssertTrue(mockAttachments.deleteAllConversationIds.isEmpty)
        }
    }
}
