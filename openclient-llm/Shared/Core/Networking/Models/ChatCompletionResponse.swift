//
//  ChatCompletionResponse.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

nonisolated struct ChatCompletionResponse: Decodable, Sendable {
    let id: String
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Decodable, Sendable {
        let message: Message
        let finishReason: String?
    }

    struct Message: Decodable, Sendable {
        let role: String
        let content: String?
        let reasoningContent: String?
        let images: [ImageItem]?
        let toolCalls: [ToolCall]?
    }

    struct ImageItem: Decodable, Sendable {
        let imageUrl: ImageItemURL
        let index: Int?
        let type: String?
    }

    struct ImageItemURL: Decodable, Sendable {
        let url: String
    }

    struct Usage: Decodable, Sendable {
        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?
    }
}
