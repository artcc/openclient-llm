//
//  AgentStreamUseCase+Streaming.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 01/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

extension AgentStreamUseCase {
    func request(
        context: AgentLoopContext,
        messages: [ChatMessage],
        tools: [ToolDefinition]
    ) async throws -> (response: ChatCompletionResponse, streamed: Bool) {
        try checkRequestIsCurrent(context)
        let stream = repository.streamAgentCompletion(
            messages: messages,
            model: context.model,
            parameters: context.parameters,
            tools: tools.isEmpty ? nil : tools
        )
        var response: ChatCompletionResponse?
        var streamed = false
        var textGate = AgentTextGate()
        for try await event in stream {
            try checkRequestIsCurrent(context)
            guard response == nil else { throw AgentStreamError.invalidResponse }
            switch event {
            case .token(let text):
                streamed = true
                if let visible = textGate.append(text) { context.continuation.yield(.token(visible)) }
            case .reasoning(let text):
                streamed = true
                context.continuation.yield(.reasoning(text))
            case .toolCallsDetected:
                context.continuation.yield(.responseDiscarded)
                textGate = AgentTextGate()
                // The round no longer has visible streamed text to discard at completion.
                streamed = false
            case .completed(let completed):
                response = completed
                finishStreamedText(&textGate, response: completed, continuation: context.continuation)
            }
        }
        try checkRequestIsCurrent(context)
        guard let response else { throw AgentStreamError.invalidResponse }
        return (response, streamed)
    }

    private func checkRequestIsCurrent(_ context: AgentLoopContext) throws {
        try Task.checkCancellation()
        guard context.isConfigurationCurrent() else { throw AgentStreamError.configurationChanged }
    }

    private func finishStreamedText(
        _ textGate: inout AgentTextGate,
        response: ChatCompletionResponse,
        continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    ) {
        guard let choice = response.choices.first,
              choice.message.toolCalls?.isEmpty != false,
              hasPresentableFinalContent(choice),
              let remaining = textGate.finish() else { return }
        continuation.yield(.token(remaining))
    }
}

/// Withholds a possible literal empty object until it becomes presentable text or the round completes.
private struct AgentTextGate {
    private var pending = ""
    private var hasReleasedText = false

    mutating func append(_ text: String) -> String? {
        guard !text.isEmpty else { return nil }
        if hasReleasedText { return text }
        pending += text
        let trimmed = pending.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !["", "{", "{}"].contains(trimmed) else { return nil }
        hasReleasedText = true
        return finish()
    }

    mutating func finish() -> String? {
        guard !pending.isEmpty else { return nil }
        let text = pending
        pending = ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines) == "{}" ? nil : text
    }
}
