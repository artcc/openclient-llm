//
//  ChatRepositoryConfigurationTests.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class ChatRepositoryConfigurationTests: XCTestCase {
    func test_streamMessage_defaultConfiguration_omitsModalities() async throws {
        // Given
        let apiClient = MockAPIClient()
        let sut = ChatRepository(apiClient: apiClient, attachmentRepository: MockAttachmentRepository())

        // When
        for try await _ in sut.streamMessage(
            messages: [ChatMessage(role: .user, content: "Hello")], model: "chat-model", parameters: .default
        ) {}

        // Then
        let payload = try encodedPayload(apiClient.lastStreamBody)
        XCTAssertEqual(apiClient.lastStreamEndpoint, "chat/completions")
        XCTAssertEqual(payload["stream"] as? Bool, true)
        XCTAssertNil(payload["modalities"])
    }

    func test_streamMessage_imageConfiguration_encodesImageAndTextModalities() async throws {
        // Given
        let apiClient = MockAPIClient()
        let sut = ChatRepository(
            apiClient: apiClient,
            attachmentRepository: MockAttachmentRepository(),
            responseModalities: ["image", "text"],
            requestTimeoutInterval: 600
        )

        // When
        for try await _ in sut.streamMessage(
            messages: [ChatMessage(role: .user, content: "Draw a cat")], model: "image-model", parameters: .default
        ) {}

        // Then
        let payload = try encodedPayload(apiClient.lastStreamBody)
        XCTAssertEqual(payload["modalities"] as? [String], ["image", "text"])
        XCTAssertEqual(payload["model"] as? String, "image-model")
        XCTAssertEqual(payload["stream"] as? Bool, true)
        XCTAssertEqual((payload["stream_options"] as? [String: Bool])?["include_usage"], true)
        XCTAssertNil(payload["tools"])
        XCTAssertNil(payload["tool_choice"])
    }

    func test_agentCompletion_defaultConfiguration_omitsModalitiesAndUses60Seconds() async throws {
        // Given
        let apiClient = MockAPIClient()
        apiClient.requestResult = try MockChatRepository().agentCompletionResult.get()
        let sut = ChatRepository(apiClient: apiClient, attachmentRepository: MockAttachmentRepository())

        // When
        _ = try await sut.agentCompletion(
            messages: [ChatMessage(role: .user, content: "Hello")],
            model: "chat-model", parameters: .default, tools: nil
        )

        // Then
        let payload = try encodedPayload(apiClient.lastRequestBody)
        XCTAssertEqual(apiClient.lastRequestEndpoint, "chat/completions")
        XCTAssertEqual(apiClient.lastRequestTimeoutInterval, 60)
        XCTAssertEqual(payload["stream"] as? Bool, false)
        XCTAssertNil(payload["modalities"])
        XCTAssertNil(payload["tools"])
        XCTAssertNil(payload["tool_choice"])
    }

    func test_agentCompletion_imageConfiguration_encodesModalitiesAndUses600Seconds() async throws {
        // Given
        let apiClient = MockAPIClient()
        apiClient.requestResult = try MockChatRepository().agentCompletionResult.get()
        let sut = ChatRepository(
            apiClient: apiClient,
            attachmentRepository: MockAttachmentRepository(),
            responseModalities: ["image", "text"],
            requestTimeoutInterval: 600
        )

        // When
        _ = try await sut.agentCompletion(
            messages: [ChatMessage(role: .user, content: "Draw a cat")],
            model: "image-model", parameters: .default, tools: nil
        )

        // Then
        let payload = try encodedPayload(apiClient.lastRequestBody)
        XCTAssertEqual(apiClient.lastRequestTimeoutInterval, 600)
        XCTAssertEqual(payload["modalities"] as? [String], ["image", "text"])
        XCTAssertEqual(payload["model"] as? String, "image-model")
        XCTAssertEqual(payload["stream"] as? Bool, false)
        XCTAssertNil(payload["tools"])
        XCTAssertNil(payload["tool_choice"])
    }

    func test_sendMessage_visionWithImageConfiguration_preservesNilModalitiesAndDefaultTimeout() async throws {
        // Given
        let apiClient = MockAPIClient()
        apiClient.requestResult = try MockChatRepository().agentCompletionResult.get()
        let sut = ChatRepository(
            apiClient: apiClient,
            attachmentRepository: MockAttachmentRepository(),
            responseModalities: ["image", "text"],
            requestTimeoutInterval: 600
        )
        let imageData = Data([0x01, 0x02])
        let attachment = ChatMessage.Attachment(
            type: .image, fileName: "reference.png", mimeType: "image/png",
            fileRelativePath: "", transientData: imageData
        )

        // When
        _ = try await sut.sendMessage(
            messages: [ChatMessage(role: .user, content: "Describe this image", attachments: [attachment])],
            model: "vision-model", parameters: .default
        )

        // Then
        let payload = try encodedPayload(apiClient.lastRequestBody)
        XCTAssertEqual(apiClient.lastRequestTimeoutInterval, 60)
        XCTAssertNil(payload["modalities"])
        XCTAssertEqual(payload["stream"] as? Bool, false)
        let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        let parts = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts.first?["text"] as? String, "Describe this image")
        let imageURL = try XCTUnwrap(parts.last?["image_url"] as? [String: String])
        XCTAssertEqual(imageURL["url"], "data:image/png;base64,\(imageData.base64EncodedString())")
    }

    // MARK: - Private

    private func encodedPayload(_ body: (any Encodable & Sendable)?) throws -> [String: Any] {
        let body = try XCTUnwrap(body)
        let data = try JSONEncoder().encode(body)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
