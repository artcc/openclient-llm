//
//  ExportConversationUseCaseTests.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 03/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class ExportConversationUseCaseTests: XCTestCase {
    // MARK: - Properties

    var sut: ExportConversationUseCase!

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()
        sut = ExportConversationUseCase()
    }

    override func tearDown() async throws {
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Tests

    func test_execute_returnsValidJSON() throws {
        // Given
        let conversation = Conversation(
            title: "Test Conversation",
            modelId: "gpt-4",
            messages: [
                ChatMessage(role: .user, content: "Hello"),
                ChatMessage(role: .assistant, content: "Hi there!")
            ]
        )

        // When
        let data = try sut.execute(conversation)

        // Then
        XCTAssertFalse(data.isEmpty)
        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["format"] as? String, ConversationExportDocument.formatIdentifier)
        XCTAssertEqual(json?["version"] as? Int, ConversationExportDocument.currentVersion)
        XCTAssertNil(json?["folders"])
        XCTAssertNil(json?["memberships"])
    }

    func test_execute_outputIsPrettyPrinted() throws {
        // Given
        let conversation = Conversation(modelId: "gpt-4")

        // When
        let data = try sut.execute(conversation)
        let string = String(data: data, encoding: .utf8) ?? ""

        // Then — pretty-printed JSON contains newlines
        XCTAssertTrue(string.contains("\n"))
    }

    func test_execute_encodesAllMessages() throws {
        // Given
        let messages = (1...5).map { idx in
            ChatMessage(role: idx % 2 == 0 ? .assistant : .user, content: "Message \(idx)")
        }
        let conversation = Conversation(modelId: "gpt-4", messages: messages)

        // When
        let data = try sut.execute(conversation)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ConversationExportDocument.self, from: data)

        // Then
        XCTAssertEqual(decoded.conversations.first?.conversation.messages.count, 5)
    }

    func test_execute_roundTrip_preservesConversation() throws {
        // Given
        let original = Conversation(
            title: "Round-trip Test",
            modelId: "llama3",
            systemPrompt: "Be helpful",
            messages: [ChatMessage(role: .user, content: "Test")]
        )

        // When
        let data = try sut.execute(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ConversationExportDocument.self, from: data)
        let importedConversation = try XCTUnwrap(decoded.conversations.first?.conversation)

        // Then
        XCTAssertEqual(importedConversation.id, original.id)
        XCTAssertEqual(importedConversation.title, original.title)
        XCTAssertEqual(importedConversation.modelId, original.modelId)
        XCTAssertEqual(importedConversation.systemPrompt, original.systemPrompt)
        XCTAssertEqual(importedConversation.messages.count, original.messages.count)
    }

    func test_execute_attachmentInStorage_embedsPortableData() throws {
        // Given
        let repository = MockAttachmentRepository()
        let attachment = ChatMessage.Attachment(
            type: .pdf,
            fileName: "document.pdf",
            mimeType: "application/pdf",
            fileRelativePath: "Attachments/conversation/document.pdf"
        )
        let message = ChatMessage(role: .user, content: "Read this", attachments: [attachment])
        let conversation = Conversation(modelId: "gpt-4", messages: [message])
        repository.loadedData = Data("document contents".utf8)
        sut = ExportConversationUseCase(attachmentRepository: repository)

        // When
        let data = try sut.execute(conversation)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(ConversationExportDocument.self, from: data)

        // Then
        let exportedAttachment = try XCTUnwrap(document.conversations.first?.attachments.first)
        XCTAssertEqual(exportedAttachment.messageId, message.id)
        XCTAssertEqual(exportedAttachment.attachmentId, attachment.id)
        XCTAssertEqual(exportedAttachment.data, Data("document contents".utf8).base64EncodedString())
    }
}
