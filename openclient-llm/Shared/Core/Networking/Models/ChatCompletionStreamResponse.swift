//
//  ChatCompletionStreamResponse.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

nonisolated struct ChatCompletionStreamResponse: Decodable, Sendable {
    let id: String
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Decodable, Sendable {
        let delta: Delta
        let finishReason: String?
    }

    struct Delta: Decodable, Sendable {
        let role: String?
        let content: String?
        let reasoningContent: String?
        let images: [ChatCompletionResponse.ImageItem]?
        let toolCalls: [ToolCall]?
    }

    struct Usage: Decodable, Sendable {
        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?
    }
}
