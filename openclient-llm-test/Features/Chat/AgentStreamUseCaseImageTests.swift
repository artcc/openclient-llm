//
//  AgentStreamUseCaseImageTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class AgentStreamUseCaseImageTests: XCTestCase {
    func test_execute_imageTool_emitsImagesWithoutAddingBytesToTranscriptOrContext() async throws {
        // Given
        let images = [makeImage("first"), makeImage("second", mimeType: "image/webp")]
        let tool = MockAgentImageTool(name: "generate_image") {
            ToolExecutionResult(text: String(repeating: "Generated image. ", count: 1_000), images: images)
        }
        let repository = makeRepository(calls: [makeCall("generate_image")])
        let sut = AgentStreamUseCase(repository: repository, chunkDelay: .zero)

        // When
        let observed = await collect(stream(sut, tools: [tool]))

        // Then
        XCTAssertNil(observed.error)
        XCTAssertEqual(observed.images, images)
        XCTAssertTrue(observed.nativeImages.isEmpty)
        XCTAssertEqual(observed.completedToolIds, ["generate_image"])
        XCTAssertTrue(observed.didComplete)
        XCTAssertEqual(observed.transcript.map(\.role), [.assistant, .tool])
        let result = try XCTUnwrap(observed.transcript.last)
        XCTAssertEqual(observed.toolTexts, [result.content])
        XCTAssertLessThanOrEqual(result.content.utf8.count, 12_000)
        XCTAssertTrue(result.content.hasSuffix("[Tool result truncated]"))
        XCTAssertEqual(repository.requests.count, 2)
        let context = try XCTUnwrap(repository.requests.last)
        XCTAssertEqual(Array(context.suffix(2)), observed.transcript)
        for message in observed.transcript + context {
            XCTAssertTrue(message.attachments.isEmpty)
            for image in images {
                XCTAssertFalse(message.content.contains(image.data.base64EncodedString()))
                let text = try XCTUnwrap(String(data: image.data, encoding: .utf8))
                XCTAssertFalse(message.content.contains(text))
            }
        }
    }

    func test_execute_textOnlyTool_keepsCompletionWithoutImageEvents() async {
        // Given
        let tool = MockAgentImageTool(name: "text_only") { ToolExecutionResult(text: "Text only") }
        let repository = makeRepository(calls: [makeCall("text_only")])
        let sut = AgentStreamUseCase(repository: repository, chunkDelay: .zero)

        // When
        let observed = await collect(stream(sut, tools: [tool]))

        // Then
        XCTAssertNil(observed.error)
        XCTAssertTrue(observed.images.isEmpty)
        XCTAssertTrue(observed.nativeImages.isEmpty)
        XCTAssertEqual(observed.completedToolIds, ["text_only"])
        XCTAssertEqual(observed.toolTexts, ["Text only"])
        XCTAssertTrue(observed.didComplete)
    }

    func test_execute_parallelImageTools_emitsBeforeSiblingCompletesButOrdersTranscriptByRequest() async {
        // Given
        let gate = AsyncStream<Void>.makeStream()
        defer { gate.continuation.finish() }
        let slowStarted = expectation(description: "Slow tool started")
        let fastImageEmitted = expectation(description: "Fast image emitted while slow tool is suspended")
        let slowImage = makeImage("slow")
        let fastImages = [makeImage("fast-1"), makeImage("fast-2")]
        let slow = MockAgentImageTool(name: "slow") {
            slowStarted.fulfill()
            for await _ in gate.stream { break }
            try Task.checkCancellation()
            return ToolExecutionResult(text: "Slow result", images: [slowImage])
        }
        let fast = MockAgentImageTool(name: "fast") {
            ToolExecutionResult(text: "Fast result", images: fastImages)
        }
        let repository = makeRepository(calls: [makeCall("slow"), makeCall("fast")])
        let sut = AgentStreamUseCase(repository: repository, chunkDelay: .zero)
        let consumer = Task {
            await collect(stream(sut, tools: [slow, fast])) { image in
                if image == fastImages.last { fastImageEmitted.fulfill() }
            }
        }
        defer { consumer.cancel() }

        // When
        await fulfillment(of: [slowStarted, fastImageEmitted], timeout: 2)
        gate.continuation.yield(())
        let observed = await consumer.value

        // Then
        XCTAssertNil(observed.error)
        XCTAssertEqual(observed.images, fastImages + [slowImage])
        XCTAssertEqual(Set(observed.completedToolIds), Set(["fast", "slow"]))
        XCTAssertEqual(observed.completedToolIds.count, 2)
        XCTAssertEqual(observed.transcript.compactMap(\.toolCallId), ["slow", "fast"])
        XCTAssertEqual(
            repository.requests.last?.filter { $0.role == .tool }.map(\.content),
            ["Slow result", "Fast result"]
        )
    }

    func test_execute_siblingFailsAfterImageCompletion_keepsAlreadyEmittedImages() async {
        // Given
        let gate = AsyncStream<Void>.makeStream()
        defer { gate.continuation.finish() }
        let imageEmitted = expectation(description: "Image emitted before sibling failure")
        let image = makeImage("survives-failure")
        let failing = MockAgentImageTool(name: "failing") {
            for await _ in gate.stream { break }
            throw AgentStreamError.configurationChanged
        }
        let generating = MockAgentImageTool(name: "generating") {
            ToolExecutionResult(text: "Generated", images: [image])
        }
        let repository = makeRepository(calls: [makeCall("failing"), makeCall("generating")])
        let sut = AgentStreamUseCase(repository: repository, chunkDelay: .zero)
        let consumer = Task {
            await collect(stream(sut, tools: [failing, generating])) { _ in imageEmitted.fulfill() }
        }
        defer { consumer.cancel() }

        // When
        await fulfillment(of: [imageEmitted], timeout: 2)
        gate.continuation.yield(())
        let observed = await consumer.value

        // Then
        XCTAssertEqual(observed.images, [image])
        XCTAssertEqual(observed.error as? AgentStreamError, .configurationChanged)
        XCTAssertTrue(observed.transcript.isEmpty)
        XCTAssertFalse(observed.didComplete)
        XCTAssertEqual(repository.requests.count, 1)
    }

    func test_execute_siblingCancellation_discardsImagesReturnedByCancelledTool() async {
        // Given
        let started = AsyncStream<Void>.makeStream()
        let suspended = AsyncStream<Void>.makeStream()
        defer {
            started.continuation.finish()
            suspended.continuation.finish()
        }
        let image = makeImage("cancelled-output")
        let generating = MockAgentImageTool(name: "generating") {
            started.continuation.yield(())
            for await _ in suspended.stream { break }
            // Deliberately return a late image after AsyncStream stops on task-group cancellation.
            return ToolExecutionResult(text: "Late result", images: [image])
        }
        let cancelling = MockAgentImageTool(name: "cancelling") {
            for await _ in started.stream { break }
            throw CancellationError()
        }
        let repository = makeRepository(calls: [makeCall("generating"), makeCall("cancelling")])
        let sut = AgentStreamUseCase(repository: repository, chunkDelay: .zero)

        // When
        let observed = await collect(stream(sut, tools: [generating, cancelling]))

        // Then
        XCTAssertTrue(observed.error is CancellationError)
        XCTAssertTrue(observed.images.isEmpty)
        XCTAssertTrue(observed.completedToolIds.isEmpty)
        XCTAssertTrue(observed.transcript.isEmpty)
        XCTAssertFalse(observed.didComplete)
        XCTAssertEqual(repository.requests.count, 1)
    }

    func test_execute_configurationChangesDuringImageTool_discardsImages() async {
        // Given
        let configuration = ImageAgentConfiguration()
        let image = makeImage("stale-output")
        let tool = MockAgentImageTool(name: "generating") {
            configuration.isCurrent = false
            return ToolExecutionResult(text: "Stale result", images: [image])
        }
        let repository = makeRepository(calls: [makeCall("generating")])
        let sut = AgentStreamUseCase(repository: repository, chunkDelay: .zero)

        // When
        let observed = await collect(sut.execute(
            messages: [ChatMessage(role: .user, content: "Generate an image")],
            model: "test",
            parameters: .default,
            toolContext: AgentToolContext(
                toolRegistry: ToolRegistry(tools: [tool]),
                isConfigurationCurrent: { configuration.isCurrent }
            )
        ))

        // Then
        XCTAssertEqual(observed.error as? AgentStreamError, .configurationChanged)
        XCTAssertTrue(observed.images.isEmpty)
        XCTAssertTrue(observed.completedToolIds.isEmpty)
        XCTAssertEqual(repository.requests.count, 1)
    }

    func test_execute_consumerCancelsAfterImage_keepsImageAndCancelsPendingTool() async {
        // Given
        let suspended = AsyncStream<Void>.makeStream()
        defer { suspended.continuation.finish() }
        let pendingStarted = expectation(description: "Pending tool started")
        let pendingCancelled = expectation(description: "Pending tool received cancellation")
        let imageEmitted = expectation(description: "Completed image reached consumer")
        let image = makeImage("before-cancel")
        let pending = MockAgentImageTool(name: "pending") {
            pendingStarted.fulfill()
            for await _ in suspended.stream { break }
            if Task.isCancelled { pendingCancelled.fulfill() }
            try Task.checkCancellation()
            return ToolExecutionResult(text: "Unexpected result")
        }
        let generating = MockAgentImageTool(name: "generating") {
            ToolExecutionResult(text: "Generated", images: [image])
        }
        let repository = makeRepository(calls: [makeCall("pending"), makeCall("generating")])
        let sut = AgentStreamUseCase(repository: repository, chunkDelay: .zero)
        let consumer = Task {
            await collect(stream(sut, tools: [pending, generating])) { _ in imageEmitted.fulfill() }
        }
        defer { consumer.cancel() }

        // When
        await fulfillment(of: [pendingStarted, imageEmitted], timeout: 2)
        consumer.cancel()
        let observed = await consumer.value
        await fulfillment(of: [pendingCancelled], timeout: 2)

        // Then
        XCTAssertEqual(observed.images, [image])
        XCTAssertTrue(observed.transcript.isEmpty)
        XCTAssertFalse(observed.didComplete)
        XCTAssertEqual(repository.requests.count, 1)
    }
}

private extension AgentStreamUseCaseImageTests {
    func makeImage(_ value: String, mimeType: String = "image/png") -> GeneratedImage {
        GeneratedImage(data: Data("image-bytes-\(value)".utf8), mimeType: mimeType, revisedPrompt: value)
    }

    func makeCall(_ name: String) -> ToolCall {
        ToolCall(id: name, type: "function", function: ToolCallFunction(name: name, arguments: "{}"))
    }

    func makeRepository(calls: [ToolCall]) -> RecordingAgentRepository {
        let toolMessage = ChatCompletionResponse.Message(
            role: "assistant", content: nil, reasoningContent: nil, images: nil, toolCalls: calls
        )
        let finalMessage = ChatCompletionResponse.Message(
            role: "assistant", content: "Done", reasoningContent: nil, images: nil, toolCalls: nil
        )
        return RecordingAgentRepository(responses: [
            ChatCompletionResponse(
                id: "tools", choices: [.init(message: toolMessage, finishReason: "tool_calls")], usage: nil
            ),
            ChatCompletionResponse(
                id: "final", choices: [.init(message: finalMessage, finishReason: "stop")], usage: nil
            )
        ])
    }

    func stream(_ sut: AgentStreamUseCase, tools: [any ChatToolProtocol]) -> AsyncThrowingStream<AgentEvent, Error> {
        sut.execute(
            messages: [ChatMessage(role: .user, content: "Generate an image")],
            model: "test",
            parameters: .default,
            toolRegistry: ToolRegistry(tools: tools)
        )
    }

    func collect(
        _ stream: AsyncThrowingStream<AgentEvent, Error>,
        onImage: (GeneratedImage) -> Void = { _ in }
    ) async -> AgentImageObservation {
        var observed = AgentImageObservation()
        do {
            for try await event in stream {
                switch event {
                case .generatedImage(let image):
                    observed.images.append(image)
                    onImage(image)
                case .image(let data):
                    observed.nativeImages.append(data)
                case .toolCallCompleted(let id, let text, _):
                    observed.completedToolIds.append(id)
                    observed.toolTexts.append(text)
                case .transcriptAppended(let messages):
                    observed.transcript.append(contentsOf: messages)
                case .completed:
                    observed.didComplete = true
                default:
                    break
                }
            }
        } catch {
            observed.error = error
        }
        return observed
    }
}

@MainActor
private struct MockAgentImageTool: ChatToolProtocol {
    let name: String
    let operation: @MainActor @Sendable () async throws -> ToolExecutionResult

    var definition: ToolDefinition {
        ToolDefinition(type: "function", function: ToolFunctionDefinition(
            name: name,
            description: "Controlled test tool",
            parameters: ToolParameters(type: "object", properties: [:], required: [])
        ))
    }

    func execute(arguments: String) async throws -> ToolExecutionResult {
        try await operation()
    }
}

@MainActor
private final class ImageAgentConfiguration {
    var isCurrent = true
}

private struct AgentImageObservation {
    var images: [GeneratedImage] = []
    var nativeImages: [Data] = []
    var completedToolIds: [String] = []
    var toolTexts: [String] = []
    var transcript: [ChatMessage] = []
    var didComplete = false
    var error: Error?
}
