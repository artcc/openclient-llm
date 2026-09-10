//
//  AnalyzeImagesToolInputTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class AnalyzeImagesToolInputTests: XCTestCase {
    // MARK: - Properties

    private let repository = MockAnalyzeInputChatRepository()

    // MARK: - Tests

    func test_execute_singleImageWithin4096Tokens_sendsPreparedImageAndPreservesResultMetadata() async throws {
        // Given
        let image = attachment()
        let sut = makeSUT(images: [image], maxInputTokens: 4_096)

        // When
        let result = try await sut.execute(arguments: arguments(images: [image]))

        // Then
        XCTAssertEqual(repository.requests.count, 1)
        let messages = try XCTUnwrap(repository.requests.first)
        XCTAssertEqual(messages.map(\.role), [.system, .user])
        XCTAssertEqual(messages.last?.attachments.map(\.id), [image.id])
        XCTAssertEqual(messages.last?.attachments.first?.transientData, Data([9]))
        XCTAssertEqual(messages.last?.attachments.first?.mimeType, "image/png")
        XCTAssertEqual(repository.parameters.first?.maxTokens, 1_024)
        XCTAssertEqual(repository.modelId, "vision-model")
        let payload = try JSONDecoder().decode([String: String].self, from: Data(result.text.utf8))
        let text = try XCTUnwrap(payload["untrustedExternalToolResult"])
        XCTAssertTrue(text.contains("Vision model: vision-model"))
        XCTAssertTrue(text.contains("Untrusted image analysis (including OCR):"))
        XCTAssertTrue(result.images.isEmpty)
    }

    func test_execute_fourImagesExceed4096Tokens_rejectsWithoutRepositoryRequest() async throws {
        // Given
        let images = (0..<4).map { _ in attachment() }
        let sut = makeSUT(images: images, maxInputTokens: 4_096)

        // When / Then
        await assertInputTooLarge(sut, arguments: try arguments(images: images))
        XCTAssertTrue(repository.requests.isEmpty)
    }

    func test_execute_longValidQuestionExceeds4096Tokens_returnsActionableLocalError() async throws {
        // Given
        let image = attachment()
        let sut = makeSUT(images: [image], maxInputTokens: 4_096)
        let input = try arguments(question: String(repeating: "q", count: 4_000), images: [image])

        // When / Then
        await assertInputTooLarge(sut, arguments: input)
        XCTAssertTrue(repository.requests.isEmpty)
        XCTAssertEqual(AnalyzeImagesTool.ExecutionError.inputTooLarge.errorDescription, String(localized: """
        This image analysis request exceeds the vision model's context window. \
        Reduce the number of images, shorten the question, or choose a vision model with a larger context window.
        """))
    }

    func test_execute_missingOrNonpositiveInputLimit_preservesFullRequest() async throws {
        // Given
        let images = (0..<4).map { _ in attachment() }
        let question = String(repeating: "q", count: 4_000)
        let input = try arguments(question: question, images: images)
        let limits: [Int?] = [nil, 0, -1, Int.min]

        for limit in limits {
            let sut = makeSUT(images: images, maxOutputTokens: nil, maxInputTokens: limit)

            // When
            _ = try await sut.execute(arguments: input)

            // Then
            XCTAssertEqual(repository.requests.last?.last?.attachments.map(\.id), images.map(\.id))
            XCTAssertTrue(repository.requests.last?.last?.content.hasPrefix(question) == true)
            XCTAssertEqual(repository.parameters.last?.maxTokens, 2_048)
        }
        XCTAssertEqual(repository.requests.count, limits.count)
    }

    func test_execute_positiveInputLimitBelowOutputReservation_rejectsInsteadOfIgnoringLimit() async throws {
        // Given
        let image = attachment()
        let input = try arguments(images: [image])

        // When / Then
        for limit in [1, 1_024] {
            let sut = makeSUT(images: [image], maxInputTokens: limit)
            await assertInputTooLarge(sut, arguments: input)
        }
        XCTAssertTrue(repository.requests.isEmpty)
    }

    func test_execute_exactBuilderBoundary_reservesEffectiveOutputAndRejectsOneTokenLess() async throws {
        // Given
        let image = attachment()
        let input = try arguments(images: [image])
        let builder = ContextWindowBuilder()
        let limits: [(output: Int?, effective: Int)] = [
            (1_024, 1_024), (nil, 2_048), (0, 2_048), (-1, 2_048), (4_096, 2_048)
        ]
        for (output, effective) in limits {
            _ = try await makeSUT(images: [image], maxOutputTokens: output).execute(arguments: input)
            let messages = try XCTUnwrap(repository.requests.last)
            let system = try XCTUnwrap(messages.first)
            let estimated = builder.estimatedInputTokens(
                messages: Array(messages.dropFirst()), systemPrompt: system.content
            )
            let required = estimated + effective
            let boundary = try XCTUnwrap((1...20_000).first {
                builder.usableInputTokens(for: $0) >= required
            })
            XCTAssertEqual(builder.usableInputTokens(for: boundary), required)
            repository.requests.removeAll()

            // When
            let sut = makeSUT(images: [image], maxOutputTokens: output, maxInputTokens: boundary)
            _ = try await sut.execute(arguments: input)

            // Then
            XCTAssertEqual(repository.requests.count, 1)
            XCTAssertEqual(repository.requests.last?.map(\.role), messages.map(\.role))
            XCTAssertEqual(repository.requests.last?.map(\.content), messages.map(\.content))
            XCTAssertEqual(repository.requests.last?.map(\.attachments), messages.map(\.attachments))
            XCTAssertEqual(repository.parameters.last?.maxTokens, effective)
            repository.requests.removeAll()
            let tooSmall = makeSUT(images: [image], maxOutputTokens: output, maxInputTokens: boundary - 1)
            await assertInputTooLarge(tooSmall, arguments: input)
            XCTAssertTrue(repository.requests.isEmpty)
        }
    }

    func test_execute_catalogMetadataChangesAfterInit_keepsCapturedLimits() async throws {
        // Given
        let images = (0..<4).map { _ in attachment() }
        var model = LLMModel(id: "vision-model", maxInputTokens: 4_096, maxOutputTokens: 1_024)
        let sut = makeSUT(images: images, maxOutputTokens: model.maxOutputTokens, maxInputTokens: model.maxInputTokens)
        model.maxInputTokens = 16_384
        model.maxOutputTokens = 2_048

        // When
        _ = try await sut.execute(arguments: arguments(images: [images[0]]))

        // Then
        XCTAssertEqual(repository.parameters.last?.maxTokens, 1_024)
        repository.requests.removeAll()
        await assertInputTooLarge(sut, arguments: try arguments(images: images))
        XCTAssertTrue(repository.requests.isEmpty)
    }

    // MARK: - Private

    private func makeSUT(
        images: [ChatMessage.Attachment], maxOutputTokens: Int? = 1_024, maxInputTokens: Int? = nil
    ) -> AnalyzeImagesTool {
        let preparation = MockPrepareImageAttachmentUseCase()
        preparation.result = .success(PreparedImageAttachment(
            data: Data([9]), fileName: "prepared.png", mimeType: "image/png"
        ))
        return AnalyzeImagesTool(
            modelId: "vision-model",
            attachments: images,
            conversationId: UUID(),
            chatRepository: repository,
            attachmentRepository: MockAttachmentRepository(),
            prepareImageAttachmentUseCase: preparation,
            maxOutputTokens: maxOutputTokens,
            maxInputTokens: maxInputTokens
        )
    }

    private func attachment() -> ChatMessage.Attachment {
        ChatMessage.Attachment(
            type: .image, fileName: "image.jpg", mimeType: "image/jpeg",
            fileRelativePath: "", transientData: Data([1])
        )
    }

    private func arguments(question: String = "Describe it", images: [ChatMessage.Attachment]) throws -> String {
        let questionJSON = try XCTUnwrap(String(data: JSONEncoder().encode(question), encoding: .utf8))
        let idsJSON = try XCTUnwrap(String(data: JSONEncoder().encode(images.map(\.id)), encoding: .utf8))
        return "{\"question\":\(questionJSON),\"attachment_ids\":\(idsJSON)}"
    }

    private func assertInputTooLarge(
        _ sut: AnalyzeImagesTool, arguments: String, file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            _ = try await sut.execute(arguments: arguments)
            XCTFail("Expected local inputTooLarge rejection", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? AnalyzeImagesTool.ExecutionError, .inputTooLarge, file: file, line: line)
        }
    }
}

@MainActor
private final class MockAnalyzeInputChatRepository: ChatRepositoryProtocol {
    var requests: [[ChatMessage]] = []
    var parameters: [ModelParameters] = []
    var modelId: String?

    func sendMessage(
        messages: [ChatMessage], model: String, parameters: ModelParameters
    ) async throws -> (String, TokenUsage?) {
        requests.append(messages)
        self.parameters.append(parameters)
        modelId = model
        return ("A small cat.", nil)
    }

    func streamMessage(
        messages: [ChatMessage], model: String, parameters: ModelParameters
    ) -> AsyncThrowingStream<StreamChunk, Error> {
        XCTFail("Vision analysis must use sendMessage")
        return AsyncThrowingStream { $0.finish() }
    }

    func agentCompletion(
        messages: [ChatMessage], model: String, parameters: ModelParameters, tools: [ToolDefinition]?
    ) async throws -> ChatCompletionResponse {
        XCTFail("Vision analysis must not enter an agent loop")
        throw APIError.invalidResponse
    }
}
