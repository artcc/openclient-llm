//
//  GenerateChatImageUseCaseTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class GenerateChatImageUseCaseTests: XCTestCase {
    private let apiClient = MockAPIClient()
    private let gifBase64 = "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"

    private var sut: GenerateChatImageUseCase {
        GenerateChatImageUseCase(repository: ChatRepository(apiClient: apiClient))
    }

    func test_execute_textPrompt_usesChatStreamWithoutToolsAndReturnsFirstImage() async throws {
        // Given
        let prompt = " Generate a cat\n"
        apiClient.streamChunks = [Data("""
        {"id":"image","choices":[{"delta":{"content":"Here it is","images":[
          {"image_url":{"url":"data:image/png;base64,\(gifBase64)"},"index":0,"type":"image_url"},
          {"image_url":{"url":"data:image/gif;base64,\(gifBase64)"},"index":1,"type":"image_url"}
        ]}}]}
        """.utf8)]

        // When
        let image = try await sut.execute(prompt: prompt, model: "dual-chat", attachments: [])

        // Then
        XCTAssertEqual(image.data, Data(base64Encoded: gifBase64))
        XCTAssertEqual(image.mimeType, "image/gif")
        XCTAssertNil(image.revisedPrompt)
        XCTAssertEqual(apiClient.lastStreamEndpoint, "chat/completions")
        XCTAssertNil(apiClient.lastRequestEndpoint)
        XCTAssertNil(apiClient.lastMultipartEndpoint)
        let request = try XCTUnwrap(apiClient.lastStreamBody as? ChatCompletionRequest)
        XCTAssertEqual(request.model, "dual-chat")
        XCTAssertTrue(request.stream)
        XCTAssertNil(request.tools)
        XCTAssertNil(request.toolChoice)
        XCTAssertNil(request.modalities)
        XCTAssertEqual(request.messages.count, 1)
        let message = try XCTUnwrap(request.messages.first)
        XCTAssertEqual(message.role, "user")
        guard case .text(let content) = message.content else { return XCTFail("Expected text-only content") }
        XCTAssertEqual(content, prompt)
    }

    func test_execute_imagesWithoutIndexOrType_acceptsSharedResponseFormat() async throws {
        // Given
        apiClient.streamChunks = [Data("""
        {"id":"image","choices":[{"delta":{"images":[
          {"image_url":{"url":"data:image/gif;base64,\(gifBase64)"}}
        ]}}]}
        """.utf8)]

        // When
        let image = try await sut.execute(prompt: "Generate a cat", model: "dual-chat", attachments: [])

        // Then
        XCTAssertEqual(image.mimeType, "image/gif")
    }

    func test_execute_firstImageFollowedByFailure_returnsFirstImage() async throws {
        // Given
        let repository = MockChatRepository()
        let bytes = try XCTUnwrap(Data(base64Encoded: gifBase64))
        repository.streamChunks = [.token("Text"), .image(bytes), .image(Data())]
        repository.streamError = APIError.rateLimited
        let sut = GenerateChatImageUseCase(repository: repository)

        // When
        let image = try await sut.execute(prompt: "Generate a cat", model: "dual-chat", attachments: [])

        // Then
        XCTAssertEqual(image.data, bytes)
        XCTAssertEqual(image.mimeType, "image/gif")
    }

    func test_execute_emptyPrompt_rejectsBeforeRequest() async {
        // Given
        let prompt = " \n\t"

        // When
        do {
            _ = try await sut.execute(prompt: prompt, model: "dual-chat", attachments: [])
            XCTFail("Expected promptRequired")
        } catch {
            // Then
            guard case ImageGenerationInputError.promptRequired = error else {
                return XCTFail("Expected promptRequired, got \(error)")
            }
        }
        XCTAssertNil(apiClient.lastStreamEndpoint)
    }

    func test_execute_anyAttachments_rejectsBeforeRequest() async {
        // Given
        let attachments = [
            ChatMessage.Attachment(
                type: .image, fileName: "cat.png", mimeType: "image/png", fileRelativePath: "cat.png"
            ),
            ChatMessage.Attachment(
                type: .pdf, fileName: "cat.pdf", mimeType: "application/pdf", fileRelativePath: "cat.pdf"
            )
        ]
        for attachment in attachments {
            // When
            do {
                _ = try await sut.execute(prompt: "Generate a cat", model: "dual-chat", attachments: [attachment])
                XCTFail("Expected textOnly")
            } catch {
                // Then
                guard case ImageGenerationInputError.textOnly = error else {
                    return XCTFail("Expected textOnly, got \(error)")
                }
            }
        }
        XCTAssertNil(apiClient.lastStreamEndpoint)
    }

    func test_execute_textOnlyResponse_throwsInvalidResponse() async {
        // Given
        apiClient.streamChunks = [Data(#"{"id":"text","choices":[{"delta":{"content":"No image"}}]}"#.utf8)]

        // When
        do {
            _ = try await sut.execute(prompt: "Generate a cat", model: "dual-chat", attachments: [])
            XCTFail("Expected invalidResponse")
        } catch {
            // Then
            XCTAssertEqual(error as? APIError, .invalidResponse)
        }
    }

    func test_execute_invalidImageData_throwsInvalidResponse() async {
        // Given
        let repository = MockChatRepository()
        repository.streamChunks = [.image(Data("not an image".utf8))]
        let sut = GenerateChatImageUseCase(repository: repository)

        // When
        do {
            _ = try await sut.execute(prompt: "Generate a cat", model: "dual-chat", attachments: [])
            XCTFail("Expected invalidResponse")
        } catch {
            // Then
            XCTAssertEqual(error as? APIError, .invalidResponse)
        }
    }

    func test_execute_streamFailure_propagatesError() async {
        // Given
        apiClient.streamError = APIError.rateLimited

        // When
        do {
            _ = try await sut.execute(prompt: "Generate a cat", model: "dual-chat", attachments: [])
            XCTFail("Expected rateLimited")
        } catch {
            // Then
            XCTAssertEqual(error as? APIError, .rateLimited)
        }
    }

    func test_execute_cancelledBeforeRequest_doesNotStartStream() async {
        // Given
        let sut = sut

        // When
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await sut.execute(prompt: "Generate a cat", model: "dual-chat", attachments: [])
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            // Then
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertNil(apiClient.lastStreamEndpoint)
    }

    func test_execute_oversizedStreamImage_throwsBeforeReturningImage() async {
        // Given
        let bytes = Data(repeating: 0, count: 25 * 1_024 * 1_024 + 1)
        apiClient.streamChunks = [Data("""
        {"id":"image","choices":[{"delta":{"images":[
          {"image_url":{"url":"data:image/png;base64,\(bytes.base64EncodedString())"}}
        ]}}]}
        """.utf8)]

        // When
        do {
            _ = try await sut.execute(prompt: "Generate a cat", model: "dual-chat", attachments: [])
            XCTFail("Expected oversized image rejection")
        } catch {
            // Then
            XCTAssertEqual(error as? APIError, .invalidResponse)
        }
    }

    func test_execute_streamCancelled_propagatesCancellation() async {
        // Given
        apiClient.streamError = CancellationError()

        // When
        do {
            _ = try await sut.execute(prompt: "Generate a cat", model: "dual-chat", attachments: [])
            XCTFail("Expected cancellation")
        } catch {
            // Then
            XCTAssertTrue(error is CancellationError)
        }
    }
}
