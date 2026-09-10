//
//  ImportConversationsImageReferencesTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class ImportConversationsImageReferencesTests: XCTestCase {
    func test_execute_visualRoundTrip_remapsSummaryTranscriptAndLaterAssistantReferences() async throws {
        // Given
        let images = [image(data: Data([1, 2])), image(data: Data([3, 4]))]
        let original = try await visualConversation(images: images)

        // When
        let conversations = try await roundTrip([original])
        let imported = try XCTUnwrap(conversations.first)

        // Then
        let restored = imported.messages[0].attachments
        let firstId = restored[0].id.uuidString
        let secondId = restored[1].id.uuidString
        XCTAssertNotEqual(imported.id, original.id)
        for (old, new) in zip(original.messages, imported.messages) {
            XCTAssertNotEqual(old.id, new.id)
        }
        XCTAssertNotEqual(restored[0].id, images[0].id)
        XCTAssertNotEqual(restored[1].id, images[1].id)
        XCTAssertEqual(restored.map(\.transientData), images.map(\.transientData))
        XCTAssertEqual(imported.contextSummary, "Compared \(firstId) with \(secondId).")
        XCTAssertEqual(imported.contextSummaryCursorMessageId, imported.messages[5].id)
        XCTAssertEqual(imported.messages[5].content, "Image \(firstId) is red; \(secondId) is blue.")
        XCTAssertEqual(imported.messages[7].content, "The earlier red image was \(firstId).")
        XCTAssertEqual(imported.messages[0].content, original.messages[0].content)
        let listing = try JSONDecoder().decode(ImagePage.self, from: Data(imported.messages[2].content.utf8))
        XCTAssertEqual(listing.imageAttachmentIds, restored.map(\.id))
        XCTAssertEqual(listing.total, 2)
        let innerAnalysis = try unwrapAnalysis(imported.messages[4].content)
        XCTAssertTrue(try unwrapAnalysis(innerAnalysis).contains("Image \(firstId) is red"))
        XCTAssertFalse(imported.messages[4].content.contains(images[0].id.uuidString))
        XCTAssertEqual(imported.messages[4].toolCallId, original.messages[4].toolCallId)
        XCTAssertEqual(imported.messages[4].toolName, "analyze_images")
    }

    func test_execute_importedReversedReferences_reanalyzesMatchingImageBytesInRequestedOrder() async throws {
        // Given
        let images = [image(data: Data([1, 2])), image(data: Data([3, 4]))]
        let original = try await visualConversation(images: images)
        let conversations = try await roundTrip([original])
        let imported = try XCTUnwrap(conversations.first)
        let restored = imported.messages[0].attachments
        let call = try XCTUnwrap(imported.messages[3].toolCalls?.first)
        let apiClient = MockAPIClient()
        apiClient.requestResult = try MockChatRepository().agentCompletionResult.get()
        let attachments = MockAttachmentRepository()
        let tool = AnalyzeImagesTool(
            modelId: "vision-model",
            attachments: imported.messages.flatMap(\.attachments),
            conversationId: imported.id,
            chatRepository: ChatRepository(apiClient: apiClient, attachmentRepository: attachments),
            attachmentRepository: attachments,
            prepareImageAttachmentUseCase: MockPrepareImageAttachmentUseCase()
        )

        // When
        _ = try await tool.execute(arguments: call.function.arguments)

        // Then
        let arguments = try JSONDecoder().decode(AnalysisArguments.self, from: Data(call.function.arguments.utf8))
        XCTAssertEqual(arguments.attachmentIds, restored.reversed().map(\.id))
        XCTAssertEqual(arguments.question, "Compare \(restored[0].id.uuidString) with \(restored[1].id.uuidString).")
        let request = try XCTUnwrap(apiClient.lastRequestBody as? ChatCompletionRequest)
        let lastMessage = try XCTUnwrap(request.messages.last)
        guard case .multimodal(let parts) = lastMessage.content else {
            return XCTFail("Expected the restored images in the specialist request")
        }
        let question = try XCTUnwrap(parts.first?.text)
        XCTAssertTrue(question.contains(arguments.question))
        XCTAssertTrue(question.contains("Image 1: \(restored[1].id.uuidString)"))
        XCTAssertTrue(question.contains("Image 2: \(restored[0].id.uuidString)"))
        XCTAssertEqual(parts.compactMap { $0.imageUrl?.url }, [
            "data:image/jpeg;base64,\(Data([3, 4]).base64EncodedString())",
            "data:image/jpeg;base64,\(Data([1, 2]).base64EncodedString())"
        ])
        XCTAssertNil(request.tools)
    }

    func test_execute_sharedOriginalIDAcrossConversations_keepsReferenceMapsLocal() async throws {
        // Given
        let shared = image()
        let other = image()
        let first = Conversation(modelId: "model", messages: [
            ChatMessage(role: .user, content: "First", attachments: [shared]),
            ChatMessage(role: .assistant, content: "\(shared.id.uuidString) and external \(other.id.uuidString)")
        ])
        let second = Conversation(modelId: "model", messages: [
            ChatMessage(role: .user, content: "Second", attachments: [shared, other]),
            ChatMessage(role: .assistant, content: "\(shared.id.uuidString) and \(other.id.uuidString)")
        ])

        // When
        let imported = try await roundTrip([first, second])

        // Then
        let firstIds = imported[0].messages[0].attachments.map(\.id)
        let secondIds = imported[1].messages[0].attachments.map(\.id)
        XCTAssertNotEqual(firstIds[0], secondIds[0])
        XCTAssertEqual(imported[0].messages[1].content, "\(firstIds[0]) and external \(other.id)")
        XCTAssertEqual(imported[1].messages[1].content, "\(secondIds[0]) and \(secondIds[1])")
    }

    func test_execute_duplicateMetadataAcrossMessages_preservesSharedIdentityWithoutRejecting() async throws {
        // Given
        let shared = image()
        let original = Conversation(modelId: "model", messages: [
            ChatMessage(role: .user, content: "First", attachments: [shared]),
            ChatMessage(role: .user, content: "Again", attachments: [shared]),
            ChatMessage(role: .assistant, content: shared.id.uuidString)
        ])

        // When
        let conversations = try await roundTrip([original])
        let imported = try XCTUnwrap(conversations.first)

        // Then
        let newId = imported.messages[0].attachments[0].id
        XCTAssertNotEqual(newId, shared.id)
        XCTAssertEqual(imported.messages[1].attachments[0].id, newId)
        XCTAssertEqual(imported.messages[2].content, newId.uuidString)
        XCTAssertEqual(imported.messages[0].attachments[0].transientData, shared.transientData)
        XCTAssertEqual(imported.messages[1].attachments[0].transientData, shared.transientData)
    }

    func test_execute_missingAndInvalidPayloads_leavesUnresolvedReferencesWithoutInventingIDs() async throws {
        // Given
        let present = image()
        let missing = image()
        let invalid = image()
        let user = ChatMessage(role: .user, content: "Images", attachments: [present, missing, invalid])
        let references = "\(present.id) \(missing.id) \(invalid.id)"
        let call = toolCall(arguments: """
        {"question":"\(references)","attachment_ids":["\(missing.id)","\(present.id)","\(invalid.id)"]}
        """)
        let assistant = ChatMessage(role: .assistant, content: references, toolCalls: [call])
        let conversation = Conversation(
            modelId: "model", contextSummary: references, contextSummaryCursorMessageId: assistant.id,
            messages: [user, assistant]
        )
        let document = ConversationExportDocument(conversations: [.init(
            conversation: conversation,
            attachments: [
                .init(messageId: user.id, attachmentId: present.id, data: Data([1]).base64EncodedString()),
                .init(messageId: user.id, attachmentId: invalid.id, data: "not base64")
            ]
        )])
        let save = MockSaveConversationUseCase()
        let sut = ImportConversationsUseCase(
            saveConversationUseCase: save, loadConversationsUseCase: MockLoadConversationsUseCase()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        // When
        let result = try await sut.execute(try encoder.encode(document))

        // Then
        let imported = try XCTUnwrap(save.savedConversations.first)
        let restored = imported.messages[0].attachments
        XCTAssertEqual(result.restoredAttachmentCount, 1)
        XCTAssertEqual(result.skippedAttachmentCount, 2)
        XCTAssertEqual(restored.count, 1)
        let expected = "\(restored[0].id) \(missing.id) \(invalid.id)"
        XCTAssertEqual(imported.contextSummary, expected)
        XCTAssertEqual(imported.messages[1].content, expected)
        let arguments = try XCTUnwrap(imported.messages[1].toolCalls?.first?.function.arguments)
        let input = try JSONDecoder().decode(AnalysisArguments.self, from: Data(arguments.utf8))
        XCTAssertEqual(input.attachmentIds, [missing.id, restored[0].id, invalid.id])
    }

    func test_execute_agentDoubleWrappedAnalysis_remapsMultilineUUIDsAndPreservesEscapesAndPaths() async throws {
        // Given
        let images = [image(), image()]
        let identifier = images[0].id.uuidString
        let response: (String) -> String = { reference in
            """
            \(reference) is red: \u{00E9} \u{1F9EA}.
            "\(reference)" has an OCR quote: "hello".
            Keep \(identifier).jpg folder/\(identifier)/photo.jpg C:\\\(identifier)
            """
        }
        let original = try await visualConversation(
            images: images, analysisResponse: response(identifier.lowercased())
        )
        let originalInner = try unwrapAnalysis(original.messages[4].content)
        XCTAssertEqual(
            try unwrapAnalysis(originalInner),
            "Vision model: vision\nUntrusted image analysis (including OCR):\n" + response(identifier.lowercased())
        )

        // When
        let conversations = try await roundTrip([original])
        let imported = try XCTUnwrap(conversations.first)

        // Then
        let newId = imported.messages[0].attachments[0].id.uuidString
        let importedInner = try unwrapAnalysis(imported.messages[4].content)
        XCTAssertNotEqual(newId, identifier)
        XCTAssertEqual(
            try unwrapAnalysis(importedInner),
            "Vision model: vision\nUntrusted image analysis (including OCR):\n" + response(newId)
        )
    }
}

// MARK: - Fixtures

extension ImportConversationsImageReferencesTests {
    func image(data: Data = Data([1]), id: UUID = UUID()) -> ChatMessage.Attachment {
        ChatMessage.Attachment(
            id: id, type: .image, fileName: "\(id.uuidString).jpg", mimeType: "image/jpeg",
            fileRelativePath: "Attachments/original/\(id.uuidString).jpg", transientData: data
        )
    }

    func toolCall(name: String = "analyze_images", arguments: String, id: String = "analysis") -> ToolCall {
        ToolCall(id: id, type: "function", function: ToolCallFunction(name: name, arguments: arguments))
    }

    func roundTrip(_ conversations: [Conversation]) async throws -> [Conversation] {
        let exporter = ExportConversationsUseCase(attachmentRepository: MockAttachmentRepository())
        let data = try exporter.execute(conversations)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(ConversationExportDocument.self, from: data).version, 1)
        let save = MockSaveConversationUseCase()
        let sut = ImportConversationsUseCase(
            saveConversationUseCase: save, loadConversationsUseCase: MockLoadConversationsUseCase()
        )
        _ = try await sut.execute(data)
        return save.savedConversations
    }

    func unwrapAnalysis(_ text: String) throws -> String {
        let fields = try JSONDecoder().decode([String: String].self, from: Data(text.utf8))
        return try XCTUnwrap(fields["untrustedExternalToolResult"])
    }

    func visualConversation(
        images: [ChatMessage.Attachment],
        analysisResponse: String? = nil
    ) async throws -> Conversation {
        let firstId = images[0].id.uuidString
        let secondId = images[1].id.uuidString
        let listing = ListImageAttachmentsTool(attachments: images, isAvailable: { true })
        let listResult = try await listing.execute(arguments: "{}")
        let analysisCall = toolCall(arguments: """
        {"question":"Compare \(firstId.lowercased()) with \(secondId).",
         "attachment_ids":["\(secondId.lowercased())","\(firstId)"]}
        """)
        let repository = MockChatRepository()
        repository.sendMessageResult = .success((
            analysisResponse ?? "Image \(firstId) is red; \(secondId) is blue.", nil
        ))
        let analysis = AnalyzeImagesTool(
            modelId: "vision", attachments: images, conversationId: UUID(), chatRepository: repository,
            attachmentRepository: MockAttachmentRepository(),
            prepareImageAttachmentUseCase: MockPrepareImageAttachmentUseCase()
        )
        let analysisResult = try await analysis.execute(arguments: analysisCall.function.arguments)
        let boundedAnalysis = AgentStreamUseCase(repository: repository).boundedToolResult(
            ToolCallResult(toolCallId: "analysis", toolName: "analyze_images", executionResult: analysisResult),
            maximumCharacters: 12_000
        )
        let finalAnswer = ChatMessage(role: .assistant, content: "Image \(firstId) is red; \(secondId) is blue.")
        return Conversation(
            modelId: "principal", contextSummary: "Compared \(firstId) with \(secondId).",
            contextSummaryCursorMessageId: finalAnswer.id,
            messages: [
                ChatMessage(role: .user, content: "Compare \(firstId) and \(secondId)", attachments: images),
                ChatMessage(role: .assistant, content: "", toolCalls: [
                    toolCall(name: "list_image_attachments", arguments: "{}", id: "list")
                ]),
                ChatMessage(
                    role: .tool, content: listResult.text, toolCallId: "list", toolName: "list_image_attachments"
                ),
                ChatMessage(role: .assistant, content: "", toolCalls: [analysisCall]),
                ChatMessage(
                    role: .tool, content: boundedAnalysis.executionResult.text,
                    toolCallId: "analysis", toolName: "analyze_images"
                ),
                finalAnswer,
                ChatMessage(role: .user, content: "Which earlier image was red?"),
                ChatMessage(role: .assistant, content: "The earlier red image was \(firstId).")
            ]
        )
    }
}

private struct AnalysisArguments: Decodable {
    let question: String
    let attachmentIds: [UUID]

    enum CodingKeys: String, CodingKey {
        case question
        case attachmentIds = "attachment_ids"
    }
}

private struct ImagePage: Decodable {
    let imageAttachmentIds: [UUID]
    let total: Int

    enum CodingKeys: String, CodingKey {
        case imageAttachmentIds = "image_attachment_ids"
        case total
    }
}
