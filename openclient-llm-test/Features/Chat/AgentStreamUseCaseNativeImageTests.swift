//
//  AgentStreamUseCaseNativeImageTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class AgentStreamUseCaseNativeImageTests: XCTestCase {
    private let gifBase64 = "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"

    func test_execute_imageOnlyFinal_emitsTypedImageAndCompletesWithoutRetry() async throws {
        // Given
        for contentJSON in ["null", "\"\"", "\" {} \""] {
            let repository = MockChatRepository()
            repository.agentCompletionResult = .success(try response(
                imageURLs: ["data:image/gif;base64,\(gifBase64)"], contentJSON: contentJSON
            ))

            // When
            let events = try await execute(repository)

            // Then
            XCTAssertEqual(repository.agentCompletionCallCount, 1)
            XCTAssertEqual(images(in: events), [GeneratedImage(
                data: try XCTUnwrap(Data(base64Encoded: gifBase64)), mimeType: "image/gif", revisedPrompt: nil
            )])
            XCTAssertFalse(events.contains {
                if case .token = $0 { return true }
                return false
            })
            XCTAssertFalse(events.contains {
                if case .transcriptAppended = $0 { return true }
                return false
            })
            guard case .completed = events.last else { return XCTFail("Expected completed after image") }
        }
    }

    func test_execute_textAndImages_preservesTextReasoningAndImageOrderWithDetectedMIME() async throws {
        // Given
        let first = try XCTUnwrap(Data(base64Encoded: gifBase64))
        var second = first
        second.append(0)
        let repository = MockChatRepository()
        repository.agentCompletionResult = .success(try response(
            imageURLs: ["data:image/png;base64,\(gifBase64)", "data:image/gif;base64,\(second.base64EncodedString())"],
            contentJSON: #""Two cats""#,
            reasoningJSON: #""Planning""#
        ))

        // When
        let events = try await execute(repository)

        // Then
        XCTAssertEqual(images(in: events).map(\.data), [first, second])
        XCTAssertEqual(images(in: events).map(\.mimeType), ["image/gif", "image/gif"])
        let text = events.compactMap { event -> String? in
            if case .token(let value) = event { return value }
            return nil
        }.joined()
        let reasoning = events.compactMap { event -> String? in
            if case .reasoning(let value) = event { return value }
            return nil
        }.joined()
        XCTAssertEqual(text, "Two cats")
        XCTAssertEqual(reasoning, "Planning")
        XCTAssertEqual(repository.agentCompletionCallCount, 1)
        let imageIndices = events.indices.filter {
            if case .generatedImage = events[$0] { return true }
            return false
        }
        let firstTextIndex = try XCTUnwrap(events.firstIndex {
            switch $0 {
            case .token, .reasoning: return true
            default: return false
            }
        })
        XCTAssertTrue(imageIndices.allSatisfy { $0 < firstTextIndex })
        guard case .completed = events.last else { return XCTFail("Expected completed after final text") }
    }

    func test_hasPresentableFinalContent_imageWithPlaceholderText_isPresentable() throws {
        // Given
        let sut = AgentStreamUseCase(repository: MockChatRepository(), chunkDelay: .zero)
        for contentJSON in ["null", "\"\"", "\" {} \""] {
            let withImage = try XCTUnwrap(response(
                imageURLs: ["data:image/gif;base64,\(gifBase64)"], contentJSON: contentJSON
            ).choices.first)
            let withoutImage = try XCTUnwrap(response(imageURLs: [], contentJSON: contentJSON).choices.first)

            // When
            let hasImageContent = sut.hasPresentableFinalContent(withImage)
            let hasTextContent = sut.hasPresentableFinalContent(withoutImage)

            // Then
            XCTAssertTrue(hasImageContent)
            XCTAssertFalse(hasTextContent)
        }
    }

    func test_handleFinalChoice_invalidImageWithText_failsBeforePublishingTextOrReasoning() async throws {
        // Given
        let sut = AgentStreamUseCase(repository: MockChatRepository(), chunkDelay: .zero)
        let choice = try XCTUnwrap(response(
            imageURLs: ["data:image/png;base64,invalid"],
            contentJSON: #""Here is your image""#,
            reasoningJSON: #""Planning""#
        ).choices.first)
        let (stream, continuation) = AsyncThrowingStream<AgentEvent, Error>.makeStream()

        // When
        do {
            _ = try await sut.handleFinalChoice(choice, continuation: continuation, delay: .zero)
            XCTFail("Expected invalidResponse")
        } catch {
            // Then
            XCTAssertEqual(error as? APIError, .invalidResponse)
        }
        continuation.finish()
        var eventCount = 0
        for try await _ in stream { eventCount += 1 }
        XCTAssertEqual(eventCount, 0)
    }

    func test_execute_imageWithoutOptionalMetadata_decodesAndCompletes() async throws {
        // Given
        let repository = MockChatRepository()
        repository.agentCompletionResult = .success(try response(
            imageURLs: ["data:image/gif;base64,\(gifBase64)"], includesMetadata: false
        ))

        // When
        let events = try await execute(repository)

        // Then
        XCTAssertEqual(images(in: events).count, 1)
        XCTAssertEqual(repository.agentCompletionCallCount, 1)
        guard case .completed = events.last else { return XCTFail("Expected completed") }
    }

    func test_execute_invalidNativeImages_failsWithoutEmptySuccessOrRetry() async throws {
        // Given
        let invalidURLs = [
            "https://example.com/image.png",
            "data:image/png;base64,not-base64",
            "data:image/png;base64,\(Data("not an image".utf8).base64EncodedString())"
        ]
        for url in invalidURLs {
            let repository = MockChatRepository()
            repository.agentCompletionResult = .success(try response(imageURLs: [url]))

            // When
            do {
                _ = try await execute(repository)
                XCTFail("Expected invalidResponse")
            } catch {
                // Then
                XCTAssertEqual(error as? APIError, .invalidResponse)
            }
            XCTAssertEqual(repository.agentCompletionCallCount, 1)
        }
    }

    func test_execute_emptyImagesAndNoText_keepsInvalidFinalRetryBehavior() async throws {
        // Given
        let repository = MockChatRepository()
        repository.agentCompletionResult = .success(try response(imageURLs: []))

        // When
        do {
            _ = try await execute(repository)
            XCTFail("Expected invalidResponse after forced final retry")
        } catch {
            // Then
            XCTAssertEqual(error as? AgentStreamError, .invalidResponse)
        }
        XCTAssertEqual(repository.agentCompletionCallCount, 2)
    }

    func test_execute_oversizedNativeImage_failsInsteadOfEmittingImage() async throws {
        // Given
        let repository = MockChatRepository()
        let bytes = Data(repeating: 0, count: 25 * 1_024 * 1_024 + 1)
        repository.agentCompletionResult = .success(try response(
            imageURLs: ["data:image/png;base64,\(bytes.base64EncodedString())"]
        ))

        // When
        do {
            _ = try await execute(repository)
            XCTFail("Expected oversized image rejection")
        } catch {
            // Then
            XCTAssertEqual(error as? APIError, .invalidResponse)
        }
        XCTAssertEqual(repository.agentCompletionCallCount, 1)
    }

    // MARK: - Private

    private func response(
        imageURLs: [String],
        contentJSON: String = "null",
        reasoningJSON: String = "null",
        includesMetadata: Bool = true
    ) throws -> ChatCompletionResponse {
        let items = imageURLs.enumerated().map { index, url in
            let metadata = includesMetadata ? ",\"index\":\(index),\"type\":\"image_url\"" : ""
            return "{\"image_url\":{\"url\":\"\(url)\"}\(metadata)}"
        }.joined(separator: ",")
        let data = Data("""
        {"id":"native","choices":[{"finish_reason":"stop","message":{
          "role":"assistant","content":\(contentJSON),"reasoning_content":\(reasoningJSON),"images":[\(items)]
        }}]}
        """.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ChatCompletionResponse.self, from: data)
    }

    private func execute(_ repository: MockChatRepository) async throws -> [AgentEvent] {
        let sut = AgentStreamUseCase(repository: repository, chunkDelay: .zero)
        var events: [AgentEvent] = []
        for try await event in sut.execute(
            messages: [ChatMessage(role: .user, content: "Generate a cat")],
            model: "native-chat",
            parameters: .default,
            toolRegistry: ToolRegistry(tools: [])
        ) {
            if case .image = event { XCTFail("Native agent images must carry typed MIME metadata") }
            events.append(event)
        }
        return events
    }

    private func images(in events: [AgentEvent]) -> [GeneratedImage] {
        events.compactMap { event in
            if case .generatedImage(let image) = event { return image }
            return nil
        }
    }
}
