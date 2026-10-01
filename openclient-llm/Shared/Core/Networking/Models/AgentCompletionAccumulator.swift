//
//  AgentCompletionAccumulator.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 01/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

/// Reconstructs one completion without retaining raw SSE payloads.
nonisolated struct AgentCompletionAccumulator {
    private var responseId: String?
    private var content = ""
    private var reasoning = ""
    private var images: [ChatCompletionResponse.ImageItem] = []
    private var toolCalls: [Int: PartialToolCall] = [:]
    private var finishReason: String?
    private var usage: ChatCompletionResponse.Usage?

    mutating func append(_ chunk: ChatCompletionStreamResponse) throws -> ChatCompletionStreamResponse.Delta? {
        responseId = responseId ?? chunk.id
        if let usage = chunk.usage {
            self.usage = .init(
                promptTokens: usage.promptTokens,
                completionTokens: usage.completionTokens,
                totalTokens: usage.totalTokens
            )
        }
        guard let choice = chunk.choices.first(where: { ($0.index ?? 0) == 0 }) else { return nil }
        let delta = choice.delta
        let hasPayload = !(delta.content ?? "").isEmpty || !(delta.reasoningContent ?? "").isEmpty
            || delta.toolCalls?.isEmpty == false || delta.images?.isEmpty == false
        guard finishReason == nil || !hasPayload else { throw APIError.invalidResponse }
        content += delta.content ?? ""
        reasoning += delta.reasoningContent ?? ""
        images.append(contentsOf: delta.images ?? [])
        for fragment in delta.toolCalls ?? [] {
            guard fragment.index >= 0 else { throw APIError.invalidResponse }
            var call = toolCalls[fragment.index] ?? PartialToolCall()
            try call.append(fragment)
            toolCalls[fragment.index] = call
        }
        if let reason = choice.finishReason {
            guard finishReason == nil || finishReason == reason else { throw APIError.invalidResponse }
            finishReason = reason
        }
        return delta
    }

    func completedResponse() throws -> ChatCompletionResponse {
        // EOF (including [DONE]) without a terminal choice cannot authorize partial tool calls.
        guard let responseId, let finishReason, !finishReason.isEmpty else { throw APIError.invalidResponse }
        if !toolCalls.isEmpty, !["stop", "tool_calls"].contains(finishReason) {
            throw APIError.invalidResponse
        }
        let calls = try toolCalls.keys.sorted().compactMap { try toolCalls[$0]?.completed() }
        guard Set(calls.map(\.id)).count == calls.count else { throw APIError.invalidResponse }
        return ChatCompletionResponse(
            id: responseId,
            choices: [.init(
                message: .init(
                    role: "assistant",
                    content: content.isEmpty ? nil : content,
                    reasoningContent: reasoning.isEmpty ? nil : reasoning,
                    images: images.isEmpty ? nil : images,
                    toolCalls: calls.isEmpty ? nil : calls
                ),
                finishReason: finishReason
            )],
            usage: usage
        )
    }
}

private extension AgentCompletionAccumulator {
    nonisolated struct PartialToolCall {
        var id = ""
        var type: String?
        var name = ""
        var arguments = ""

        mutating func append(_ delta: ChatCompletionStreamResponse.ToolCallDelta) throws {
            if let type = delta.type {
                guard type == "function" else { throw APIError.invalidResponse }
                self.type = type
            }
            id += delta.id ?? ""
            name += delta.function?.name ?? ""
            arguments += delta.function?.arguments ?? ""
        }

        func completed() throws -> ToolCall {
            guard type == "function",
                  !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw APIError.invalidResponse
            }
            // Argument validation belongs to the existing registry, which returns a matching tool result on failure.
            return ToolCall(id: id, type: "function", function: .init(name: name, arguments: arguments))
        }
    }
}
