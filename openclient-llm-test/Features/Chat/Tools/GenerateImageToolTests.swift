//
//  GenerateImageToolTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class GenerateImageToolTests: XCTestCase {
    // MARK: - Properties

    private let useCase = MockGenerateImageUseCase()
    private let image = GeneratedImage(
        data: Data([1, 2, 3]), mimeType: "image/png", revisedPrompt: "Private revised prompt"
    )

    // MARK: - Tests

    func test_definition_generation_declaresTextPromptOnly() {
        // Given
        let sut = makeSUT()

        // When
        let definition = sut.definition

        // Then
        XCTAssertEqual(definition.function.name, "generate_image")
        XCTAssertEqual(definition.function.parameters.required, ["prompt"])
        XCTAssertEqual(Set(definition.function.parameters.properties.keys), ["prompt"])
        XCTAssertEqual(definition.function.parameters.properties["prompt"]?.type, "string")
    }

    func test_execute_validPrompt_returnsTypedImageWithoutEchoingImagePayload() async throws {
        // Given
        useCase.result = .success(image)
        let sut = makeSUT()

        // When
        let result = try await sut.execute(arguments: #"{"prompt":"  A small cat.\n"}"#)

        // Then
        XCTAssertEqual(useCase.prompts, ["A small cat."])
        XCTAssertEqual(useCase.models, ["image-model"])
        XCTAssertEqual(useCase.attachments, [[]])
        XCTAssertEqual(result.images, [image])
        XCTAssertTrue(result.text.contains("image-model"))
        XCTAssertFalse(result.text.contains(image.data.base64EncodedString()))
        XCTAssertFalse(result.text.contains("Private revised prompt"))
        XCTAssertFalse(result.text.contains("A small cat."))
        XCTAssertNil(result.searchResults)
        XCTAssertTrue(ToolExecutionResult(text: "Other tool result").images.isEmpty)
    }

    func test_execute_invalidArguments_rejectsWithoutConsumingTurn() async throws {
        // Given
        useCase.result = .success(image)
        let sut = makeSUT()
        let invalidInputs = ["not-json", "[]", "{}", #"{"prompt":42}"#,
                             #"{"prompt":"Cat","attachments":[]}"#,
                             #"{"prompt":"Cat","model":"other-model"}"#,
                             #"{"prompt":"Cat","url":"https://example.com/image.png"}"#,
                             String(repeating: " ", count: 65_537)]

        // When / Then
        for input in invalidInputs {
            await assertFailure(.invalidArguments, sut: sut, arguments: input)
        }
        XCTAssertEqual(useCase.executeCallCount, 0)
        _ = try await sut.execute(arguments: #"{"prompt":"Cat"}"#)
        XCTAssertEqual(useCase.executeCallCount, 1)
    }

    func test_execute_emptyOrOversizedPrompt_rejectsWithoutConsumingTurn() async throws {
        // Given
        useCase.result = .success(image)
        let sut = makeSUT()

        // When / Then
        for prompt in ["", " \n\t", String(repeating: "a", count: 8_001)] {
            await assertFailure(.invalidPrompt, sut: sut, arguments: try arguments(prompt: prompt))
        }
        XCTAssertEqual(useCase.executeCallCount, 0)
        _ = try await sut.execute(arguments: arguments(prompt: String(repeating: "a", count: 8_000)))
        XCTAssertEqual(useCase.prompts.first?.count, 8_000)
    }

    func test_execute_repeatedInvocation_keepsTurnLimitUntilNewInstance() async throws {
        // Given
        useCase.result = .success(image)
        let sut = makeSUT()
        let input = #"{"prompt":"Cat"}"#
        let registry = ToolRegistry(tools: [sut])
        XCTAssertEqual(registry.definitions.map(\.function.name), ["generate_image"])

        // When
        _ = try await sut.execute(arguments: input)
        XCTAssertTrue(registry.definitions.isEmpty)
        await assertFailure(.turnLimitReached, sut: sut, arguments: input)
        _ = try await makeSUT().execute(arguments: input)

        // Then
        XCTAssertEqual(useCase.executeCallCount, 2)
    }

    func test_execute_concurrentInvocationWhileFirstIsSuspended_startsOnlyOneRequest() async throws {
        // Given
        let started = expectation(description: "First image request started")
        var pending: CheckedContinuation<GeneratedImage, Never>?
        let image = image
        useCase.asyncExecuteHandler = { _, _, callCount in
            guard callCount == 1 else { return image }
            return await withCheckedContinuation { continuation in
                pending = continuation
                started.fulfill()
            }
        }
        let sut = makeSUT()
        let input = #"{"prompt":"Cat"}"#
        let registry = ToolRegistry(tools: [sut])

        // When
        let first = Task { @MainActor in try await sut.execute(arguments: input) }
        await fulfillment(of: [started], timeout: 1)
        XCTAssertTrue(registry.definitions.isEmpty)
        await assertFailure(.turnLimitReached, sut: sut, arguments: input)
        pending?.resume(returning: image)
        let result = try await first.value

        // Then
        XCTAssertEqual(useCase.executeCallCount, 1)
        XCTAssertEqual(result.images, [image])
    }

    func test_execute_failedOrEmptyGeneration_consumesTurnWithoutLeakingServerError() async {
        // Given
        let input = #"{"prompt":"Cat"}"#
        let results: [Result<GeneratedImage, Error>] = [
            .failure(APIError.invalidRequest("Private server response")),
            .success(GeneratedImage(data: Data(), mimeType: "image/png", revisedPrompt: nil))
        ]

        // When / Then
        for result in results {
            useCase.result = result
            let sut = makeSUT()
            let registry = ToolRegistry(tools: [sut])
            await assertFailure(.requestFailed, sut: sut, arguments: input)
            XCTAssertTrue(registry.definitions.isEmpty)
            await assertFailure(.turnLimitReached, sut: sut, arguments: input)
        }
        XCTAssertEqual(useCase.executeCallCount, 2)
        let message = GenerateImageTool.ExecutionError.requestFailed.localizedDescription
        XCTAssertFalse(message.contains("Private server response"))
    }

    func test_execute_unavailableBeforeRequest_doesNotConsumeTurn() async throws {
        // Given
        let availability = AvailabilityState()
        availability.isAvailable = false
        useCase.result = .success(image)
        let sut = makeSUT(isAvailable: { availability.isAvailable })
        let input = #"{"prompt":"Cat"}"#

        // When / Then
        await assertFailure(.unavailable, sut: sut, arguments: input)
        XCTAssertEqual(useCase.executeCallCount, 0)
        availability.isAvailable = true
        _ = try await sut.execute(arguments: input)
        XCTAssertEqual(useCase.executeCallCount, 1)
    }

    func test_execute_unavailableAfterAwait_discardsImageAndKeepsTurnConsumed() async {
        // Given
        let availability = AvailabilityState()
        let image = image
        useCase.asyncExecuteHandler = { _, _, _ in
            availability.isAvailable = false
            return image
        }
        let sut = makeSUT(isAvailable: { availability.isAvailable })
        let input = #"{"prompt":"Cat"}"#

        // When / Then
        await assertFailure(.unavailable, sut: sut, arguments: input)
        availability.isAvailable = true
        await assertFailure(.turnLimitReached, sut: sut, arguments: input)
        XCTAssertEqual(useCase.executeCallCount, 1)
    }

    func test_execute_dependencyCancellation_propagatesAndKeepsTurnConsumed() async {
        // Given
        let input = #"{"prompt":"Cat"}"#

        // When / Then
        for error in [CancellationError() as Error, URLError(.cancelled)] {
            useCase.result = .failure(error)
            let sut = makeSUT()
            await assertCancellation(sut: sut, arguments: input)
            await assertFailure(.turnLimitReached, sut: sut, arguments: input)
        }
        XCTAssertEqual(useCase.executeCallCount, 2)
    }

    func test_execute_cancelledBeforeExecution_doesNotConsumeTurn() async throws {
        // Given
        useCase.result = .success(image)
        let sut = makeSUT()
        let input = #"{"prompt":"Cat"}"#

        // When
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            await self.assertCancellation(sut: sut, arguments: input)
        }
        await task.value

        // Then
        XCTAssertEqual(useCase.executeCallCount, 0)
        _ = try await sut.execute(arguments: input)
        XCTAssertEqual(useCase.executeCallCount, 1)
    }

    func test_execute_cancelledWhileRequestReturns_discardsImageAndKeepsTurnConsumed() async {
        // Given
        let image = image
        useCase.asyncExecuteHandler = { _, _, _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return image
        }
        let sut = makeSUT()
        let input = #"{"prompt":"Cat"}"#

        // When
        let task = Task { @MainActor in await self.assertCancellation(sut: sut, arguments: input) }
        await task.value

        // Then
        await assertFailure(.turnLimitReached, sut: sut, arguments: input)
        XCTAssertEqual(useCase.executeCallCount, 1)
    }

    // MARK: - Private

    private func makeSUT(
        isAvailable: @escaping @MainActor @Sendable () -> Bool = { true }
    ) -> GenerateImageTool {
        GenerateImageTool(modelId: "image-model", generateImageUseCase: useCase, isAvailable: isAvailable)
    }

    private func arguments(prompt: String) throws -> String {
        try XCTUnwrap(String(data: JSONEncoder().encode(["prompt": prompt]), encoding: .utf8))
    }

    private func assertFailure(
        _ expected: GenerateImageTool.ExecutionError, sut: GenerateImageTool, arguments: String,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            _ = try await sut.execute(arguments: arguments)
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? GenerateImageTool.ExecutionError, expected, file: file, line: line)
        }
    }

    private func assertCancellation(sut: GenerateImageTool, arguments: String) async {
        do {
            _ = try await sut.execute(arguments: arguments)
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }
}

@MainActor
private final class AvailabilityState {
    var isAvailable = true
}
