//
//  AgentStreamUseCase+Chunking.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 21/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

nonisolated extension AgentStreamUseCase {
    func handleFinalChoice(
        _ choice: ChatCompletionResponse.Choice,
        continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation,
        delay: Duration
    ) async throws -> Bool {
        let content = choice.message.content ?? ""
        let reasoning = choice.message.reasoningContent
        guard hasPresentableFinalContent(choice) else { return true }
        guard try yieldNativeImages(choice, continuation: continuation) else { return false }
        if let reasoning, !reasoning.isEmpty {
            try await yieldChunked(
                reasoning,
                as: { .reasoning($0) },
                continuation: continuation,
                delay: delay
            )
        }
        if !content.isEmpty, content.trimmingCharacters(in: .whitespacesAndNewlines) != "{}" {
            try await yieldChunked(
                content,
                as: { .token($0) },
                continuation: continuation,
                delay: delay
            )
        }
        return false
    }

    func yieldNativeImages(
        _ choice: ChatCompletionResponse.Choice,
        continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    ) throws -> Bool {
        for item in choice.message.images ?? [] {
            try Task.checkCancellation()
            let image = try GeneratedImageDecoder.decode(dataURL: item.imageUrl.url)
            if case .terminated = continuation.yield(.generatedImage(image)) { return false }
        }
        return true
    }

    func hasPresentableFinalContent(_ choice: ChatCompletionResponse.Choice) -> Bool {
        let content = choice.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let reasoning = choice.message.reasoningContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return choice.message.images?.isEmpty == false || (content != "{}" && (!content.isEmpty || !reasoning.isEmpty))
    }

    func yieldChunked(
        _ text: String,
        as event: @Sendable (String) -> AgentEvent,
        continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation,
        delay: Duration
    ) async throws {
        let targetChunkCount = 100
        let maximumChunkCount = 300
        let minimumChunkSize = 4
        let preferredMaximumChunkSize = 48
        let adaptiveChunkSize = text.count / targetChunkCount + (text.count % targetChunkCount == 0 ? 0 : 1)
        let preferredChunkSize = min(preferredMaximumChunkSize, max(minimumChunkSize, adaptiveChunkSize))
        let minimumSizeForChunkLimit = text.count / maximumChunkCount + (text.count % maximumChunkCount == 0 ? 0 : 1)
        let chunkSize = max(preferredChunkSize, minimumSizeForChunkLimit)
        var index = text.startIndex
        while index < text.endIndex {
            try Task.checkCancellation()
            let end = text.index(index, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex
            if case .terminated = continuation.yield(event(String(text[index..<end]))) { return }
            index = end
            if index != text.endIndex && delay > Duration.zero {
                try await Task.sleep(for: delay)
            }
        }
    }
}
