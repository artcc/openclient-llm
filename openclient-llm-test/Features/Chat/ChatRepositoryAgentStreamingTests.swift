//
//  ChatRepositoryAgentStreamingTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 01/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class ChatRepositoryAgentStreamingTests: XCTestCase {
    func test_streamAgentCompletion_textAndReasoning_emitsDeltasAndCollectsTrailingUsage() async throws {
        // Given
        let api = MockAPIClient()
        api.streamChunks = try [
            AgentStreamingFixture.chunk(reasoning: "Think"),
            AgentStreamingFixture.chunk(content: "Hello "),
            AgentStreamingFixture.chunk(content: "world", finish: "stop"),
            AgentStreamingFixture.chunk(usage: ["prompt_tokens": 12, "completion_tokens": 8, "total_tokens": 20])
        ]

        // When
        let events = try await collect(makeRepository(api))
        let response = try completedResponse(events)

        // Then
        XCTAssertEqual(tokens(events), ["Hello ", "world"])
        XCTAssertEqual(response.choices.first?.message.content, "Hello world")
        XCTAssertEqual(response.choices.first?.message.reasoningContent, "Think")
        XCTAssertEqual(response.usage?.totalTokens, 20)
        XCTAssertEqual(api.streamRequestCount, 1)
        XCTAssertNil(api.lastRequestBody)
        let body = try XCTUnwrap(api.lastStreamBody as? ChatCompletionRequest)
        XCTAssertTrue(body.stream)
        XCTAssertNil(body.tools)
        XCTAssertNil(body.toolChoice)
        XCTAssertEqual(body.streamOptions?.includeUsage, true)
    }

    func test_streamAgentCompletion_interleavedCalls_reconstructsInIndexOrderWithStopReason() async throws {
        // Given
        let api = MockAPIClient()
        api.streamChunks = try [
            AgentStreamingFixture.chunk(calls: [
                AgentStreamingFixture.call(index: 1, id: "second", name: "look", arguments: "{\"city\":"),
                AgentStreamingFixture.call(index: 0, id: "first", name: "lookup", arguments: "{")
            ]),
            AgentStreamingFixture.chunk(calls: [
                AgentStreamingFixture.call(index: 0, arguments: "}"),
                AgentStreamingFixture.call(index: 1, name: "up", arguments: "\"Madrid\"}")
            ], finish: "stop")
        ]

        // When
        let response = try completedResponse(await collect(makeRepository(api)))

        // Then
        let calls = try XCTUnwrap(response.choices.first?.message.toolCalls)
        XCTAssertEqual(calls.map(\.id), ["first", "second"])
        XCTAssertEqual(calls.map(\.function.name), ["lookup", "lookup"])
        XCTAssertEqual(calls.map(\.function.arguments), ["{}", "{\"city\":\"Madrid\"}"])
    }

    func test_streamAgentCompletion_missingTerminalChoice_failsWithoutCompletedResponse() async throws {
        let api = MockAPIClient()
        api.streamChunks = [try AgentStreamingFixture.chunk(calls: [
            AgentStreamingFixture.call(id: "call", name: "lookup", arguments: "{}")
        ])]
        await assertRejected(api, expected: .invalidResponse)
    }

    func test_streamAgentCompletion_malformedChunk_doesNotSkipMissingArguments() async throws {
        let api = MockAPIClient()
        api.streamChunks = [Data("{invalid".utf8), try AgentStreamingFixture.chunk(content: "Answer", finish: "stop")]
        await assertRejected(api, expected: .decodingError)
    }

    func test_streamAgentCompletion_truncatedToolCall_failsEvenWithTerminalChoice() async throws {
        let api = MockAPIClient()
        api.streamChunks = [try AgentStreamingFixture.chunk(calls: [
            AgentStreamingFixture.call(id: "call", name: "lookup", arguments: "{")
        ], finish: "length")]
        await assertRejected(api, expected: .invalidResponse)
    }

    func test_streamAgentCompletion_missingIdentityOrDuplicateIds_rejectsCalls() async throws {
        let invalidCalls = [
            [AgentStreamingFixture.call(name: "lookup", arguments: "{}")],
            [AgentStreamingFixture.call(id: "call", arguments: "{}")],
            [AgentStreamingFixture.call(index: -1, id: "call", name: "lookup", arguments: "{}")],
            [AgentStreamingFixture.call(id: "same", name: "lookup", arguments: "{}"),
             AgentStreamingFixture.call(index: 1, id: "same", name: "lookup", arguments: "{}")]
        ]
        for calls in invalidCalls {
            let api = MockAPIClient()
            api.streamChunks = [try AgentStreamingFixture.chunk(calls: calls, finish: "tool_calls")]
            await assertRejected(api, expected: .invalidResponse)
        }
    }

    func test_streamAgentCompletion_payloadAfterTerminalChoice_rejectsModifiedResponse() async throws {
        let api = MockAPIClient()
        api.streamChunks = try [
            AgentStreamingFixture.chunk(content: "Answer", finish: "stop"),
            AgentStreamingFixture.chunk(content: "Unexpected suffix")
        ]
        await assertRejected(api, expected: .invalidResponse)
    }

    func test_streamAgentCompletion_transportFailureAfterTerminalChoice_doesNotCompleteOrRetry() async throws {
        let api = MockAPIClient()
        api.streamChunks = [try AgentStreamingFixture.chunk(content: "Partial", finish: "stop")]
        api.streamError = APIError.serverUnreachable
        await assertRejected(api, expected: .serverUnreachable)
        XCTAssertEqual(api.streamRequestCount, 1)
        XCTAssertNil(api.lastRequestBody)
    }

    func test_streamAgentCompletion_nativeImages_preservesBufferedTransportAndTimeout() async throws {
        // Given
        let api = MockAPIClient()
        api.requestResult = try MockChatRepository().agentCompletionResult.get()
        let repository = ChatRepository(
            apiClient: api, attachmentRepository: MockAttachmentRepository(),
            responseModalities: ["image", "text"], requestTimeoutInterval: 600
        )

        // When
        let events = try await collect(repository)

        // Then
        _ = try completedResponse(events)
        XCTAssertTrue(tokens(events).isEmpty)
        XCTAssertEqual(api.streamRequestCount, 0)
        XCTAssertEqual(api.lastRequestTimeoutInterval, 600)
        let body = try XCTUnwrap(api.lastRequestBody as? ChatCompletionRequest)
        XCTAssertFalse(body.stream)
        XCTAssertEqual(body.modalities, ["image", "text"])
    }

    // MARK: - Private

    private func makeRepository(_ api: MockAPIClient) -> ChatRepository {
        ChatRepository(apiClient: api, attachmentRepository: MockAttachmentRepository())
    }

    private func collect(_ repository: ChatRepository) async throws -> [AgentCompletionEvent] {
        var events: [AgentCompletionEvent] = []
        for try await event in repository.streamAgentCompletion(
            messages: [ChatMessage(role: .user, content: "Question")],
            model: "test", parameters: .default, tools: nil
        ) { events.append(event) }
        return events
    }

    private func completedResponse(_ events: [AgentCompletionEvent]) throws -> ChatCompletionResponse {
        let responses = events.compactMap { event -> ChatCompletionResponse? in
            if case .completed(let response) = event { return response }
            return nil
        }
        XCTAssertEqual(responses.count, 1)
        return try XCTUnwrap(responses.first)
    }

    private func tokens(_ events: [AgentCompletionEvent]) -> [String] {
        events.compactMap { if case .token(let text) = $0 { text } else { nil } }
    }

    private func assertRejected(_ api: MockAPIClient, expected: APIError) async {
        var didComplete = false
        do {
            for try await event in makeRepository(api).streamAgentCompletion(
                messages: [], model: "test", parameters: .default, tools: nil
            ) {
                if case .completed = event { didComplete = true }
            }
            XCTFail("Expected stream rejection")
        } catch {
            XCTAssertEqual(error as? APIError, expected)
        }
        XCTAssertFalse(didComplete)
    }
}
