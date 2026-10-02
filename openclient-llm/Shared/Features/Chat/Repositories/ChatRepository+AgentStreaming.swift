//
//  ChatRepository+AgentStreaming.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 01/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

extension ChatRepository {
    func streamAgentCompletion(
        messages: [ChatMessage],
        model: String,
        parameters: ModelParameters,
        tools: [ToolDefinition]?
    ) -> AsyncThrowingStream<AgentCompletionEvent, Error> {
        // Native image rounds retain their image-first completion and request timeout policy.
        if responseModalities?.contains("image") == true {
            return bufferedAgentCompletion(messages: messages, model: model, parameters: parameters, tools: tools)
        }
        let request = ChatCompletionRequest(
            model: model,
            messages: buildCompletionMessages(messages),
            stream: true,
            temperature: parameters.temperature,
            maxTokens: parameters.maxTokens,
            topP: parameters.topP,
            streamOptions: ChatStreamOptions(includeUsage: true),
            modalities: responseModalities,
            tools: tools,
            toolChoice: tools != nil ? "auto" : nil
        )
        let dataStream = apiClient.streamRequest(endpoint: "chat/completions", body: request)
        return AsyncThrowingStream { continuation in
            let task = Task {
                await receiveAgentStream(dataStream, continuation: continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func receiveAgentStream(
        _ dataStream: AsyncThrowingStream<Data, Error>,
        continuation: AsyncThrowingStream<AgentCompletionEvent, Error>.Continuation
    ) async {
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            var accumulator = AgentCompletionAccumulator()
            var hasToolCalls = false
            for try await data in dataStream {
                try Task.checkCancellation()
                let chunk: ChatCompletionStreamResponse
                do {
                    chunk = try decoder.decode(ChatCompletionStreamResponse.self, from: data)
                } catch {
                    throw APIError.decodingError
                }
                if !hasToolCalls,
                   chunk.choices.first(where: { ($0.index ?? 0) == 0 })?.delta.toolCalls?.isEmpty == false {
                    hasToolCalls = true
                    continuation.yield(.toolCallsDetected)
                }
                let delta = try accumulator.append(chunk)
                guard !hasToolCalls else { continue }
                if let reasoning = delta?.reasoningContent, !reasoning.isEmpty {
                    continuation.yield(.reasoning(reasoning))
                }
                if let content = delta?.content, !content.isEmpty {
                    continuation.yield(.token(content))
                }
            }
            try Task.checkCancellation()
            continuation.yield(.completed(try accumulator.completedResponse()))
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }
}

extension ChatRepositoryProtocol {
    func streamAgentCompletion(
        messages: [ChatMessage],
        model: String,
        parameters: ModelParameters,
        tools: [ToolDefinition]?
    ) -> AsyncThrowingStream<AgentCompletionEvent, Error> {
        bufferedAgentCompletion(messages: messages, model: model, parameters: parameters, tools: tools)
    }

    func bufferedAgentCompletion(
        messages: [ChatMessage],
        model: String,
        parameters: ModelParameters,
        tools: [ToolDefinition]?
    ) -> AsyncThrowingStream<AgentCompletionEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try Task.checkCancellation()
                    let response = try await agentCompletion(
                        messages: messages, model: model, parameters: parameters, tools: tools
                    )
                    try Task.checkCancellation()
                    continuation.yield(.completed(response))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
