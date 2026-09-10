//
//  ImportConversationsUseCaseTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 13/07/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class ImportConversationsUseCaseTests: XCTestCase {
    // MARK: - Properties

    var mockSaveConversation: MockSaveConversationUseCase!
    var mockLoadConversations: MockLoadConversationsUseCase!
    var sut: ImportConversationsUseCase!

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()
        mockSaveConversation = MockSaveConversationUseCase()
        mockLoadConversations = MockLoadConversationsUseCase()
        sut = ImportConversationsUseCase(
            saveConversationUseCase: mockSaveConversation,
            loadConversationsUseCase: mockLoadConversations
        )
    }

    override func tearDown() async throws {
        sut = nil
        mockLoadConversations = nil
        mockSaveConversation = nil
        try await super.tearDown()
    }

    // MARK: - Tests

    func test_execute_userAttemptWithoutTranscript_preservesReservationWithNewMessageId() async throws {
        // Given
        let user = ChatMessage(role: .user, content: "Draw a cat", imageGenerationAttempted: true)
        let document = ConversationExportDocument(conversations: [.init(
            conversation: Conversation(modelId: "principal", messages: [user]), attachments: []
        )])

        // When
        _ = try await sut.execute(try encoded(document))

        // Then
        let restored = try XCTUnwrap(mockSaveConversation.savedConversations.first?.messages.first)
        XCTAssertEqual(restored.imageGenerationAttempted, true)
        XCTAssertNotEqual(restored.id, user.id)
    }

    func test_execute_validDocument_restoresConversationWithNewIdentifiers() async throws {
        // Given
        let attachment = makeAttachment()
        let message = ChatMessage(role: .user, content: "Hello", attachments: [attachment])
        let oldDate = Date(timeIntervalSince1970: 1_000_000)
        let conversation = Conversation(modelId: "gpt-4", messages: [message], updatedAt: oldDate)
        let document = ConversationExportDocument(conversations: [
            .init(
                conversation: conversation,
                attachments: [.init(messageId: message.id, attachmentId: attachment.id, data: "hello".base64Encoded)]
            )
        ])

        // When
        let result = try await sut.execute(try encoded(document))

        // Then
        let imported = try XCTUnwrap(mockSaveConversation.savedConversations.first)
        XCTAssertEqual(result.importedConversationCount, 1)
        XCTAssertEqual(result.restoredAttachmentCount, 1)
        XCTAssertNotEqual(imported.id, conversation.id)
        XCTAssertNotEqual(imported.messages[0].id, message.id)
        XCTAssertEqual(imported.messages[0].attachments[0].transientData, Data("hello".utf8))
        XCTAssertTrue(imported.messages[0].attachments[0].fileRelativePath.isEmpty)
        XCTAssertGreaterThan(imported.updatedAt, oldDate)
    }

    func test_execute_invalidAttachmentData_importsConversationWithoutAttachment() async throws {
        // Given
        let attachment = makeAttachment()
        let message = ChatMessage(role: .user, content: "Hello", attachments: [attachment])
        let conversation = Conversation(modelId: "gpt-4", messages: [message])
        let document = ConversationExportDocument(conversations: [
            .init(
                conversation: conversation,
                attachments: [.init(messageId: message.id, attachmentId: attachment.id, data: "invalid base64")]
            )
        ])

        // When
        let result = try await sut.execute(try encoded(document))

        // Then
        XCTAssertEqual(result.importedConversationCount, 1)
        XCTAssertEqual(result.skippedAttachmentCount, 1)
        XCTAssertTrue(mockSaveConversation.savedConversations[0].messages[0].attachments.isEmpty)
    }

    func test_execute_invalidAttachmentReference_throwsWithoutPersisting() async throws {
        // Given
        let conversation = Conversation(modelId: "gpt-4")
        let document = ConversationExportDocument(conversations: [
            .init(
                conversation: conversation,
                attachments: [.init(messageId: UUID(), attachmentId: UUID(), data: "data")]
            )
        ])

        // When / Then
        await assertImportThrows(try encoded(document))
        XCTAssertTrue(mockSaveConversation.savedConversations.isEmpty)
    }

    func test_execute_saveConversationFails_leavesNoPersistedConversation() async throws {
        // Given
        let attachment = makeAttachment()
        let message = ChatMessage(role: .user, content: "Hello", attachments: [attachment])
        let document = ConversationExportDocument(conversations: [
            .init(
                conversation: Conversation(modelId: "gpt-4", messages: [message]),
                attachments: [.init(messageId: message.id, attachmentId: attachment.id, data: "hello".base64Encoded)]
            )
        ])
        mockSaveConversation.error = NSError(domain: "test", code: 1)

        // When / Then
        await assertImportThrows(try encoded(document))
        XCTAssertTrue(mockSaveConversation.savedConversations.isEmpty)
    }

    func test_execute_branchedConversations_remapsBranchReferences() async throws {
        // Given
        let rootMessage = ChatMessage(role: .user, content: "Root")
        let root = Conversation(modelId: "gpt-4", messages: [rootMessage])
        let branch = Conversation(
            modelId: "gpt-4",
            parentConversationId: root.id,
            branchedFromMessageId: rootMessage.id
        )
        let document = ConversationExportDocument(conversations: [
            .init(conversation: root, attachments: []),
            .init(conversation: branch, attachments: [])
        ])

        // When
        _ = try await sut.execute(try encoded(document))

        // Then
        let importedRoot = mockSaveConversation.savedConversations[0]
        let importedBranch = mockSaveConversation.savedConversations[1]
        XCTAssertEqual(importedBranch.parentConversationId, importedRoot.id)
        XCTAssertEqual(importedBranch.branchedFromMessageId, importedRoot.messages[0].id)
    }

    func test_execute_nonEmptyBranchBackup_restoresUniqueMessagesSummaryAndAttachment() async throws {
        // Given
        let rootMessage = ChatMessage(role: .user, content: "Root")
        let root = Conversation(modelId: "gpt-4", messages: [rootMessage])
        let attachment = makeAttachment()
        let branchMessage = ChatMessage(role: .user, content: "Root", attachments: [attachment])
        let branch = Conversation(
            modelId: "gpt-4",
            contextSummary: "Root summary",
            contextSummaryCursorMessageId: branchMessage.id,
            messages: [branchMessage],
            parentConversationId: root.id,
            branchedFromMessageId: rootMessage.id
        )
        let document = ConversationExportDocument(conversations: [
            .init(conversation: root, attachments: []),
            .init(
                conversation: branch,
                attachments: [
                    .init(messageId: branchMessage.id, attachmentId: attachment.id, data: "branch".base64Encoded)
                ]
            )
        ])

        // When
        _ = try await sut.execute(try encoded(document))

        // Then
        let importedRoot = mockSaveConversation.savedConversations[0]
        let importedBranch = mockSaveConversation.savedConversations[1]
        XCTAssertFalse(importedBranch.messages.isEmpty)
        XCTAssertNotEqual(importedBranch.messages[0].id, importedRoot.messages[0].id)
        XCTAssertEqual(importedBranch.contextSummaryCursorMessageId, importedBranch.messages[0].id)
        XCTAssertEqual(importedBranch.branchedFromMessageId, importedRoot.messages[0].id)
        XCTAssertEqual(importedBranch.messages[0].attachments[0].transientData, Data("branch".utf8))
    }

    func test_execute_withAttachment_materializesBytesThroughAtomicConversationPersistence() async throws {
        // Given
        let documentsURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: documentsURL) }
        let attachmentRepository = MockAttachmentRepository()
        let repository = ConversationRepository(
            settingsManager: MockSettingsManager(),
            cloudSyncManager: MockCloudSyncManager(),
            attachmentRepository: attachmentRepository,
            baseDirectory: documentsURL
        )
        sut = ImportConversationsUseCase(
            saveConversationUseCase: SaveConversationUseCase(repository: repository),
            loadConversationsUseCase: mockLoadConversations
        )
        let attachment = makeAttachment()
        let message = ChatMessage(role: .user, content: "Document", attachments: [attachment])
        let document = ConversationExportDocument(conversations: [
            .init(
                conversation: Conversation(modelId: "gpt-4", messages: [message]),
                attachments: [.init(messageId: message.id, attachmentId: attachment.id, data: "bytes".base64Encoded)]
            )
        ])

        // When
        _ = try await sut.execute(try encoded(document))

        // Then
        let localConversations = try await repository.loadLocal()
        let imported = try XCTUnwrap(localConversations.first)
        let restoredAttachment = try XCTUnwrap(imported.messages.first?.attachments.first)
        XCTAssertTrue(attachmentRepository.savedAttachments.isEmpty)
        XCTAssertEqual(
            try Data(contentsOf: documentsURL.appendingPathComponent(restoredAttachment.fileRelativePath)),
            Data("bytes".utf8)
        )
    }

    func test_execute_cloudEnabled_publishesOnlyAfterCompleteLocalBatch() async throws {
        // Given
        let documentsURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: documentsURL) }
        let settings = MockSettingsManager()
        settings.isCloudSyncEnabled = true
        let cloud = MockCloudSyncManager()
        let probe = ImportBatchProbe()
        cloud.loadConversationsSendableHandler = {
            let directory = documentsURL.appendingPathComponent("Conversations", isDirectory: true)
            let count = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "json" }.count) ?? 0
            probe.record(count)
        }
        let repository = ConversationRepository(
            settingsManager: settings,
            cloudSyncManager: cloud,
            attachmentRepository: MockAttachmentRepository(),
            baseDirectory: documentsURL
        )
        sut = ImportConversationsUseCase(
            saveConversationUseCase: SaveConversationUseCase(repository: repository),
            loadConversationsUseCase: mockLoadConversations
        )
        let document = ConversationExportDocument(conversations: [
            .init(conversation: Conversation(modelId: "first"), attachments: []),
            .init(conversation: Conversation(modelId: "second"), attachments: [])
        ])

        // When
        _ = try await sut.execute(try encoded(document))

        // Then
        XCTAssertEqual(probe.value, 2)
        XCTAssertEqual(cloud.cloudConversations.count, 2)
    }

    func test_execute_summaryWithoutCursor_throwsWithoutPersisting() async throws {
        // Given
        let conversation = Conversation(modelId: "gpt-4", contextSummary: "Summary")
        let document = ConversationExportDocument(conversations: [
            .init(conversation: conversation, attachments: [])
        ])

        // When / Then
        await assertImportThrows(try encoded(document))
        XCTAssertTrue(mockSaveConversation.savedConversations.isEmpty)
    }

    func test_execute_cursorOutsideConversation_throwsWithoutPersisting() async throws {
        // Given
        let conversation = Conversation(
            modelId: "gpt-4",
            contextSummary: "Summary",
            contextSummaryCursorMessageId: UUID(),
            messages: [ChatMessage(role: .user, content: "Hello")]
        )
        let document = ConversationExportDocument(conversations: [
            .init(conversation: conversation, attachments: [])
        ])

        // When / Then
        await assertImportThrows(try encoded(document))
        XCTAssertTrue(mockSaveConversation.savedConversations.isEmpty)
    }

    func test_execute_nonPositiveContextWindow_throwsWithoutPersisting() async throws {
        // Given
        let conversation = Conversation(modelId: "gpt-4", contextWindowTokens: 0)
        let document = ConversationExportDocument(conversations: [
            .init(conversation: conversation, attachments: [])
        ])

        // When / Then
        await assertImportThrows(try encoded(document))
        XCTAssertTrue(mockSaveConversation.savedConversations.isEmpty)
    }

    func test_execute_validSummaryAndCursor_remapsCursor() async throws {
        // Given
        let message = ChatMessage(role: .user, content: "Hello")
        let conversation = Conversation(
            modelId: "gpt-4",
            contextSummary: "Summary",
            contextSummaryCursorMessageId: message.id,
            messages: [message]
        )
        let document = ConversationExportDocument(conversations: [
            .init(conversation: conversation, attachments: [])
        ])

        // When
        _ = try await sut.execute(try encoded(document))

        // Then
        let imported = try XCTUnwrap(mockSaveConversation.savedConversations.first)
        XCTAssertEqual(imported.contextSummaryCursorMessageId, imported.messages.first?.id)
    }

    func test_execute_cursorInsideToolRound_throwsWithoutPersisting() async throws {
        // Given
        let call = ToolCall(
            id: "call_1",
            type: "function",
            function: ToolCallFunction(name: "search", arguments: "{}")
        )
        let assistant = ChatMessage(role: .assistant, content: "", toolCalls: [call])
        let tool = ChatMessage(role: .tool, content: "Result", toolCallId: call.id, toolName: "search")
        let conversation = Conversation(
            modelId: "gpt-4",
            contextSummary: "Summary",
            contextSummaryCursorMessageId: assistant.id,
            messages: [assistant, tool]
        )
        let document = ConversationExportDocument(conversations: [
            .init(conversation: conversation, attachments: [])
        ])

        // When / Then
        await assertImportThrows(try encoded(document))
        XCTAssertTrue(mockSaveConversation.savedConversations.isEmpty)
    }

    func test_execute_tagAlreadyExistsLocally_reusesLocalColor() async throws {
        // Given
        mockLoadConversations.result = .success([
            Conversation(
                modelId: "gpt-4",
                tags: [ConversationTag(name: "swift", color: .blue)]
            )
        ])
        let conversation = Conversation(
            modelId: "gpt-4",
            tags: [ConversationTag(name: "swift", color: .red)]
        )
        let document = ConversationExportDocument(conversations: [
            .init(conversation: conversation, attachments: [])
        ])

        // When
        _ = try await sut.execute(try encoded(document))

        // Then
        XCTAssertEqual(
            mockSaveConversation.savedConversations.first?.tags,
            [ConversationTag(name: "swift", color: .blue)]
        )
    }
}

// Safety: All mutable state is protected by `NSLock`.
private final class ImportBatchProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func record(_ value: Int) {
        lock.withLock { count = value }
    }
}

// MARK: - Private

private extension ImportConversationsUseCaseTests {
    func assertImportThrows(_ data: Data) async {
        do {
            _ = try await sut.execute(data)
            XCTFail("Expected import to throw")
        } catch {
            return
        }
    }

    func makeAttachment() -> ChatMessage.Attachment {
        ChatMessage.Attachment(
            type: .pdf,
            fileName: "document.pdf",
            mimeType: "application/pdf",
            fileRelativePath: "Attachments/original/document.pdf"
        )
    }

    func encoded(_ document: ConversationExportDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }
}

private extension String {
    var base64Encoded: String {
        Data(utf8).base64EncodedString()
    }
}
