//
//  AgentStreamUseCaseDiscardTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 01/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class AgentStreamUseCaseDiscardTests: XCTestCase {
    func test_execute_pendingToolRound_discardsBeforeFailureAndSuppressesFurtherProgress() async throws {
        // Given
        let api = MockAPIClient()
        let source = AsyncThrowingStream<Data, Error>.makeStream()
        api.streamOverride = source.stream
        let tool = DiscardCountingTool()
        let discarded = expectation(description: "Tool progress discarded while the request is still pending")
        let consumer = Task { () -> ([AgentEvent], Error?) in
            var events: [AgentEvent] = []
            do {
                for try await event in makeStream(api, tool: tool) {
                    events.append(event)
                    if case .responseDiscarded = event { discarded.fulfill() }
                }
                return (events, nil)
            } catch { return (events, error) }
        }
        defer { source.continuation.finish(); consumer.cancel() }

        // When
        source.continuation.yield(try AgentStreamingFixture.chunk(content: "Checking", reasoning: "Planning"))
        source.continuation.yield(try AgentStreamingFixture.chunk(
            content: "Tool-only text", reasoning: "Tool-only reasoning",
            calls: [AgentStreamingFixture.call(id: "call", name: tool.name, arguments: "{")]
        ))
        await fulfillment(of: [discarded], timeout: 2)
        XCTAssertEqual(tool.executionCount, 0)
        source.continuation.yield(try AgentStreamingFixture.chunk(content: "Late text", reasoning: "Late reasoning"))
        source.continuation.yield(try AgentStreamingFixture.chunk(
            calls: [AgentStreamingFixture.call(arguments: "}")], finish: "tool_calls"
        ))
        source.continuation.finish(throwing: APIError.serverUnreachable)
        let (events, error) = await consumer.value

        // Then
        XCTAssertEqual(error as? APIError, .serverUnreachable)
        XCTAssertEqual(events.compactMap { if case .token(let text) = $0 { text } else { nil } }, ["Checking"])
        XCTAssertEqual(events.compactMap { if case .reasoning(let text) = $0 { text } else { nil } }, ["Planning"])
        assertDiscardedWithoutExecution(events, api: api, tool: tool)
    }

    func test_execute_invalidToolRounds_discardProgressWithoutExecutionOrRetry() async throws {
        // Given
        let call = AgentStreamingFixture.call(id: "call", name: "lookup", arguments: "{}")
        let scenarios: [(chunks: [Data], error: APIError)] = try [
            ([AgentStreamingFixture.chunk(calls: [call], finish: "length")], .invalidResponse),
            ([AgentStreamingFixture.chunk(calls: [
                AgentStreamingFixture.call(name: "lookup", arguments: "{}")
            ], finish: "tool_calls")], .invalidResponse),
            ([AgentStreamingFixture.chunk(calls: [
                AgentStreamingFixture.call(index: -1, id: "call", name: "lookup", arguments: "{}")
            ])], .invalidResponse),
            ([AgentStreamingFixture.chunk(calls: [call]), Data("{invalid".utf8)], .decodingError),
            ([AgentStreamingFixture.chunk(calls: [call])], .invalidResponse)
        ]
        for scenario in scenarios {
            let api = MockAPIClient()
            let tool = DiscardCountingTool()
            api.streamChunks = [try AgentStreamingFixture.chunk(content: "Checking", reasoning: "Planning")]
                + scenario.chunks
            var events: [AgentEvent] = []

            // When
            do {
                for try await event in makeStream(api, tool: tool) { events.append(event) }
                XCTFail("Expected invalid tool round")
            } catch {
                XCTAssertEqual(error as? APIError, scenario.error)
            }

            // Then
            assertDiscardedWithoutExecution(events, api: api, tool: tool)
        }
    }

    private func makeStream(_ api: MockAPIClient, tool: DiscardCountingTool) -> AsyncThrowingStream<AgentEvent, Error> {
        AgentStreamUseCase(
            repository: ChatRepository(apiClient: api, attachmentRepository: MockAttachmentRepository()),
            chunkDelay: .zero
        ).execute(messages: [], model: "test", parameters: .default, toolRegistry: ToolRegistry(tools: [tool]))
    }

    private func assertDiscardedWithoutExecution(
        _ events: [AgentEvent], api: MockAPIClient, tool: DiscardCountingTool
    ) {
        XCTAssertEqual(events.filter { if case .responseDiscarded = $0 { true } else { false } }.count, 1)
        XCTAssertFalse(events.contains {
            switch $0 {
            case .toolCallStarted, .transcriptAppended, .completed: true
            default: false
            }
        })
        XCTAssertEqual(tool.executionCount, 0)
        XCTAssertEqual(api.streamRequestCount, 1)
    }
}

@MainActor
private final class DiscardCountingTool: ChatToolProtocol {
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
