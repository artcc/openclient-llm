//
//  AgentStreamUseCaseStreamingTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 01/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class AgentStreamUseCaseStreamingTests: XCTestCase {
    func test_execute_pendingCompletion_deliversReasoningBeforeFinishingWithoutReplayingText() async throws {
        // Given
        let api = MockAPIClient()
        let source = AsyncThrowingStream<Data, Error>.makeStream()
        api.streamOverride = source.stream
        let reasoningReceived = expectation(description: "Reasoning arrives before completion")
        let consumer = Task {
            var events: [AgentEvent] = []
            for try await event in makeStream(api) {
                events.append(event)
                if case .reasoning("Thinking now") = event { reasoningReceived.fulfill() }
            }
            return events
        }
        defer { source.continuation.finish(); consumer.cancel() }

        // When: the completion is deliberately withheld until the first reasoning reaches the consumer.
        source.continuation.yield(try AgentStreamingFixture.chunk(reasoning: "Thinking now"))
        await fulfillment(of: [reasoningReceived], timeout: 2)
        source.continuation.yield(try AgentStreamingFixture.chunk(content: "Final "))
        source.continuation.yield(try AgentStreamingFixture.chunk(content: "answer", finish: "stop"))
        source.continuation.finish()
        let events = try await consumer.value

        // Then
        XCTAssertEqual(tokens(events), ["Final ", "answer"])
        XCTAssertEqual(reasoning(events), ["Thinking now"])
        XCTAssertEqual(api.streamRequestCount, 1)
        XCTAssertNil(api.lastRequestBody)
        guard case .completed = events.last else { return XCTFail("Expected completed response") }
    }

    func test_execute_fragmentedToolRound_executesOnceAndPreservesTranscriptAndUsage() async throws {
        // Given
        let api = MockAPIClient()
        let tool = StreamingCountingTool()
        api.streamResponses = try [
            [AgentStreamingFixture.chunk(content: "Checking", reasoning: "Need a tool"),
             AgentStreamingFixture.chunk(calls: [
                AgentStreamingFixture.call(id: "call", name: tool.name, arguments: "{")
             ]),
             AgentStreamingFixture.chunk(calls: [AgentStreamingFixture.call(arguments: "}")], finish: "stop"),
             AgentStreamingFixture.chunk(usage: ["prompt_tokens": 10, "completion_tokens": 2, "total_tokens": 12])],
            [AgentStreamingFixture.chunk(reasoning: "Now I know"),
             AgentStreamingFixture.chunk(content: "Final answer", finish: "stop"),
             AgentStreamingFixture.chunk(usage: ["prompt_tokens": 20, "completion_tokens": 3, "total_tokens": 23])]
        ]

        // When
        let events = try await collect(makeStream(api, tools: [tool]))

        // Then
        XCTAssertEqual(tool.executionCount, 1)
        XCTAssertEqual(api.streamRequestCount, 2)
        let discardIndex = try XCTUnwrap(events.firstIndex { if case .responseDiscarded = $0 { true } else { false } })
        let startIndex = try XCTUnwrap(events.firstIndex { if case .toolCallStarted = $0 { true } else { false } })
        XCTAssertLessThan(discardIndex, startIndex)
        XCTAssertEqual(events.filter { if case .responseDiscarded = $0 { true } else { false } }.count, 1)
        let transcript = events.flatMap { event -> [ChatMessage] in
            if case .transcriptAppended(let messages) = event { return messages }
            return []
        }
        XCTAssertEqual(transcript.map(\.role), [.assistant, .tool])
        XCTAssertEqual(transcript.first?.toolCalls?.first?.function.arguments, "{}")
        XCTAssertEqual(transcript.last?.toolCallId, "call")
        let request = try XCTUnwrap(api.lastStreamBody as? ChatCompletionRequest)
        XCTAssertEqual(request.messages.last?.role, "tool")
        XCTAssertEqual(request.messages.last?.toolCallId, "call")
        XCTAssertEqual(request.messages.dropLast().last?.toolCalls?.first?.id, "call")
        XCTAssertEqual(request.tools?.map(\.function.name), [tool.name])
        let usage = events.compactMap { event -> TokenUsage? in
            if case .usage(let value) = event { return value }
            return nil
        }
        XCTAssertEqual(usage.last?.totalTokens, 35)
        XCTAssertEqual(tokens(Array(events.suffix(from: discardIndex))), ["Final answer"])
    }

    func test_execute_incompleteToolRound_doesNotExecuteOrRetry() async throws {
        let api = MockAPIClient()
        let tool = StreamingCountingTool()
        api.streamChunks = [try AgentStreamingFixture.chunk(calls: [
            AgentStreamingFixture.call(id: "call", name: tool.name, arguments: "{}")
        ])]
        do {
            _ = try await collect(makeStream(api, tools: [tool]))
            XCTFail("Expected incomplete response error")
        } catch {
            XCTAssertEqual(error as? APIError, .invalidResponse)
        }
        XCTAssertEqual(tool.executionCount, 0)
        XCTAssertEqual(api.streamRequestCount, 1)
    }

    func test_execute_fragmentedEmptyObject_discardsProgressAndRetriesWithoutTools() async throws {
        // Given
        let api = MockAPIClient()
        let tool = StreamingCountingTool()
        api.streamResponses = try [
            [AgentStreamingFixture.chunk(content: " {", reasoning: "First attempt"),
             AgentStreamingFixture.chunk(content: "} ", finish: "stop")],
            [AgentStreamingFixture.chunk(reasoning: "Final reasoning"),
             AgentStreamingFixture.chunk(content: "Answer", finish: "stop")]
        ]

        // When
        let events = try await collect(makeStream(api, tools: [tool]))

        // Then
        XCTAssertEqual(tokens(events), ["Answer"])
        XCTAssertTrue(events.contains { if case .responseDiscarded = $0 { true } else { false } })
        XCTAssertEqual(tool.executionCount, 0)
        XCTAssertEqual(api.streamRequestCount, 2)
        let request = try XCTUnwrap(api.lastStreamBody as? ChatCompletionRequest)
        XCTAssertNil(request.tools)
        XCTAssertNil(request.toolChoice)
    }

    func test_execute_bracePrefixedValidText_preservesEveryCharacter() async throws {
        let api = MockAPIClient()
        api.streamChunks = try [
            AgentStreamingFixture.chunk(content: " {"),
            AgentStreamingFixture.chunk(content: "} is an empty object.", finish: "stop")
        ]
        let events = try await collect(makeStream(api))
        XCTAssertEqual(tokens(events).joined(), " {} is an empty object.")
        XCTAssertEqual(api.streamRequestCount, 1)
    }

    func test_execute_cancelledWhileModelIsPending_terminatesUpstreamWithoutExecutingTools() async throws {
        // Given
        let api = MockAPIClient()
        let tool = StreamingCountingTool()
        let source = AsyncThrowingStream<Data, Error>.makeStream()
        let received = expectation(description: "Received partial reasoning")
        let terminated = expectation(description: "Cancelled upstream stream")
        source.continuation.onTermination = { _ in terminated.fulfill() }
        api.streamOverride = source.stream
        let consumer = Task {
            for try await event in makeStream(api, tools: [tool]) {
                if case .reasoning = event { received.fulfill() }
            }
        }
        defer { consumer.cancel(); source.continuation.finish() }

        // When
        source.continuation.yield(try AgentStreamingFixture.chunk(reasoning: "Working"))
        await fulfillment(of: [received], timeout: 2)
        consumer.cancel()
        _ = try? await consumer.value
        await fulfillment(of: [terminated], timeout: 2)

        // Then
        XCTAssertEqual(tool.executionCount, 0)
        XCTAssertEqual(api.streamRequestCount, 1)
    }

    func test_execute_streamedImageWithPlaceholder_doesNotPublishEmptyObject() async throws {
        // Given
        let api = MockAPIClient()
        let image = "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"
        api.streamChunks = [Data("""
        {"id":"image","choices":[{"index":0,"finish_reason":"stop","delta":{
        "content":"{}","images":[{"image_url":{"url":"data:image/gif;base64,\(image)"}}]
        }}]}
        """.utf8)]

        // When
        let events = try await collect(makeStream(api))

        // Then
        XCTAssertTrue(tokens(events).isEmpty)
        let images = events.compactMap { event -> GeneratedImage? in
            if case .generatedImage(let image) = event { return image }
            return nil
        }
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images.first?.mimeType, "image/gif")
        guard case .completed = events.last else { return XCTFail("Expected completed image response") }
    }

    func test_execute_configurationChangesDuringStream_rejectsLateCompletion() async throws {
        let api = MockAPIClient()
        let source = AsyncThrowingStream<Data, Error>.makeStream()
        api.streamOverride = source.stream
        let scope = StreamingTestScope()
        let received = expectation(description: "Received initial reasoning")
        let useCase = AgentStreamUseCase(repository: makeRepository(api), chunkDelay: .zero)
        let consumer = Task { () -> Error? in
            do {
                for try await event in useCase.execute(
                    messages: [], model: "test", parameters: .default,
                    toolContext: AgentToolContext(
                        toolRegistry: ToolRegistry(tools: []), isConfigurationCurrent: { scope.isCurrent }
                    )
                ) {
                    if case .reasoning = event { received.fulfill() }
                }
                return nil
            } catch { return error }
        }
        defer { consumer.cancel(); source.continuation.finish() }
        source.continuation.yield(try AgentStreamingFixture.chunk(reasoning: "Working"))
        await fulfillment(of: [received], timeout: 2)
        scope.isCurrent = false
        source.continuation.yield(try AgentStreamingFixture.chunk(content: "Stale", finish: "stop"))
        source.continuation.finish()
        let error = await consumer.value
        XCTAssertEqual(error as? AgentStreamError, .configurationChanged)
        XCTAssertEqual(api.streamRequestCount, 1)
    }

    // MARK: - Private

    private func makeRepository(_ api: MockAPIClient) -> ChatRepository {
        ChatRepository(apiClient: api, attachmentRepository: MockAttachmentRepository())
    }

    private func makeStream(
        _ api: MockAPIClient, tools: [any ChatToolProtocol] = []
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AgentStreamUseCase(repository: makeRepository(api), chunkDelay: .zero).execute(
            messages: [ChatMessage(role: .user, content: "Question")],
            model: "test", parameters: .default, toolRegistry: ToolRegistry(tools: tools)
        )
    }

    private func collect(_ stream: AsyncThrowingStream<AgentEvent, Error>) async throws -> [AgentEvent] {
        var events: [AgentEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    private func tokens(_ events: [AgentEvent]) -> [String] {
        events.compactMap { if case .token(let text) = $0 { text } else { nil } }
    }

    private func reasoning(_ events: [AgentEvent]) -> [String] {
        events.compactMap { if case .reasoning(let text) = $0 { text } else { nil } }
    }
}

@MainActor
private final class StreamingCountingTool: ChatToolProtocol {
    let name = "lookup"
    private(set) var executionCount = 0

    var definition: ToolDefinition {
        ToolDefinition(type: "function", function: .init(
            name: name, description: "Test tool", parameters: .init(type: "object", properties: [:], required: [])
        ))
    }

    func execute(arguments: String) async throws -> ToolExecutionResult {
        executionCount += 1
        return ToolExecutionResult(text: "Result")
    }
}

@MainActor
private final class StreamingTestScope {
    var isCurrent = true
}
