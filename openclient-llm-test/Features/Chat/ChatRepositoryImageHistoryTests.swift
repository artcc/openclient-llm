//
//  ChatRepositoryImageHistoryTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 01/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class ChatRepositoryImageHistoryTests: XCTestCase {
    func test_requests_followUpAfterGeneratedImage_onlyEncodeImagePartsAsUserInput() async throws {
        for transport in Transport.allCases {
            // Given
            let image = try imageAttachment()
            let history = generatedImageHistory(image)
            let api = MockAPIClient()
            api.requestResult = try MockChatRepository().agentCompletionResult.get()
            api.streamChunks = [try AgentStreamingFixture.chunk(content: "Done", finish: "stop")]
            let sut = ChatRepository(
                apiClient: api, attachmentRepository: MockAttachmentRepository(),
                responseModalities: transport == .nativeAgentStream ? ["image", "text"] : nil
            )

            // When
            try await performRequest(transport, repository: sut, messages: history)
            let messages = try encodedMessages(api.lastStreamBody ?? api.lastRequestBody)

            // Then
            XCTAssertEqual(messages.compactMap { $0["role"] as? String }, history.map(\.role.rawValue))
            let calls = try XCTUnwrap(messages[2]["tool_calls"] as? [[String: Any]])
            XCTAssertEqual(calls.first?["id"] as? String, "generate-cat")
            XCTAssertEqual(messages[3]["tool_call_id"] as? String, "generate-cat")
            XCTAssertEqual(messages[4]["content"] as? String, "Here is the cat.")
            let parts = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
            let imageParts = parts.filter { $0["type"] as? String == "image_url" }
            XCTAssertEqual(imageParts.count, 1)
            let url = try XCTUnwrap(imageParts.first?["image_url"] as? [String: String])
            let base64 = try XCTUnwrap(image.transientData).base64EncodedString()
            XCTAssertEqual(url["url"], "data:image/gif;base64,\(base64)")
            XCTAssertTrue((parts.first?["text"] as? String)?.contains(image.id.uuidString) == true)
            XCTAssertEqual(parts.last?["text"] as? String, "Change the background but keep the same cat.")
            XCTAssertEqual(history[4].attachments, [image])
            XCTAssertEqual(history[4].role, .assistant)
            for message in messages where message["role"] as? String != "user" {
                let nonUserParts = message["content"] as? [[String: Any]] ?? []
                XCTAssertFalse(nonUserParts.contains { $0["type"] as? String == "image_url" })
            }
        }
    }

    func test_requests_currentUserImage_preservesBothHistoricalAndCurrentImages() async throws {
        // Given
        let previous = try imageAttachment()
        let current = try imageAttachment()
        var history = generatedImageHistory(previous)
        history[5].attachments = [current]
        let api = MockAPIClient()
        api.requestResult = try MockChatRepository().agentCompletionResult.get()
        let sut = ChatRepository(apiClient: api, attachmentRepository: MockAttachmentRepository())

        // When
        _ = try await sut.agentCompletion(messages: history, model: "vision", parameters: .default, tools: nil)

        // Then
        let messages = try encodedMessages(api.lastRequestBody)
        let parts = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
        XCTAssertEqual(parts.filter { $0["type"] as? String == "image_url" }.count, 2)
        XCTAssertTrue((parts.first?["text"] as? String)?.contains(previous.id.uuidString) == true)
        XCTAssertEqual(history[5].attachments, [current])
    }

    func test_requests_imageOnToolCallMessage_defersVisualContextUntilAfterToolResults() async throws {
        // Given
        let image = try imageAttachment()
        var history = generatedImageHistory(image)
        history[2].attachments = [image]
        history = Array(history.prefix(4))
        let api = MockAPIClient()
        api.requestResult = try MockChatRepository().agentCompletionResult.get()
        let sut = ChatRepository(apiClient: api, attachmentRepository: MockAttachmentRepository())

        // When
        _ = try await sut.agentCompletion(messages: history, model: "vision", parameters: .default, tools: nil)

        // Then
        let messages = try encodedMessages(api.lastRequestBody)
        XCTAssertEqual(messages.compactMap { $0["role"] as? String }, ["system", "user", "assistant", "tool", "user"])
        XCTAssertEqual(messages[3]["tool_call_id"] as? String, "generate-cat")
        XCTAssertTrue(messages[2]["content"] is NSNull)
        let parts = try XCTUnwrap(messages[4]["content"] as? [[String: Any]])
        XCTAssertEqual(parts.filter { $0["type"] as? String == "image_url" }.count, 1)
    }

    func test_requests_modelWithoutVision_keepsReferencesWithoutSendingImageBytes() async throws {
        // Given
        let image = try imageAttachment()
        let projected = ImageAttachmentContext.messagesForModel(
            generatedImageHistory(image), model: LLMModel(id: "text")
        )
        let api = MockAPIClient()
        api.requestResult = try MockChatRepository().agentCompletionResult.get()
        let sut = ChatRepository(apiClient: api, attachmentRepository: MockAttachmentRepository())

        // When
        _ = try await sut.agentCompletion(messages: projected, model: "text", parameters: .default, tools: nil)

        // Then
        let messages = try encodedMessages(api.lastRequestBody)
        XCTAssertEqual(messages.count, projected.count)
        XCTAssertTrue((messages[4]["content"] as? String)?.contains(image.id.uuidString) == true)
        XCTAssertTrue(messages.allSatisfy { $0["content"] is String || $0["content"] is NSNull })
    }

    private enum Transport: CaseIterable {
        case message, messageStream, agent, agentStream, nativeAgentStream
    }

    private func performRequest(
        _ transport: Transport, repository: ChatRepository, messages: [ChatMessage]
    ) async throws {
        switch transport {
        case .message:
            _ = try await repository.sendMessage(messages: messages, model: "vision", parameters: .default)
        case .messageStream:
            for try await _ in repository.streamMessage(messages: messages, model: "vision", parameters: .default) {}
        case .agent:
            _ = try await repository.agentCompletion(
                messages: messages, model: "vision", parameters: .default, tools: nil
            )
        case .agentStream, .nativeAgentStream:
            for try await _ in repository.streamAgentCompletion(
                messages: messages, model: "vision", parameters: .default, tools: nil
            ) {}
        }
    }

    private func imageAttachment() throws -> ChatMessage.Attachment {
        let data = try XCTUnwrap(Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"))
        return ChatMessage.Attachment(
            type: .image, fileName: "cat.gif", mimeType: "image/gif", fileRelativePath: "", transientData: data
        )
    }

    private func generatedImageHistory(_ image: ChatMessage.Attachment) -> [ChatMessage] {
        [
            ChatMessage(role: .system, content: "Help edit images."),
            ChatMessage(role: .user, content: "Generate a cat."),
            ChatMessage(role: .assistant, content: "", toolCalls: [
                ToolCall(id: "generate-cat", type: "function", function: .init(name: "generate_image", arguments: "{}"))
            ]),
            ChatMessage(
                role: .tool, content: "Generated one image.", toolCallId: "generate-cat", toolName: "generate_image"
            ),
            ChatMessage(role: .assistant, content: "Here is the cat.", attachments: [image]),
            ChatMessage(role: .user, content: "Change the background but keep the same cat.")
        ]
    }

    private func encodedMessages(_ body: (any Encodable & Sendable)?) throws -> [[String: Any]] {
        let body = try XCTUnwrap(body)
        let encoded = try JSONEncoder().encode(body)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        return try XCTUnwrap(payload["messages"] as? [[String: Any]])
    }
}
