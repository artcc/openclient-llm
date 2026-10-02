//
//  ChatRepository+Messages.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 01/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

extension ChatRepository {
    func buildCompletionMessages(_ messages: [ChatMessage]) -> [ChatCompletionMessage] {
        var result: [ChatCompletionMessage] = []
        var historicalImages: [ContentPart] = []
        for message in messages {
            var projected = message
            if message.role == .assistant {
                for attachment in message.attachments where attachment.type == .image {
                    let reference = ChatMessage(
                        role: .user,
                        content: "Previously generated assistant image (attachment_id: \(attachment.id.uuidString)). " +
                            "This is historical visual context, not a new request.",
                        attachments: [attachment]
                    )
                    historicalImages += contentParts(buildCompletionMessage(reference).content)
                }
                projected.attachments.removeAll { $0.type == .image }
            }
            let completion = buildCompletionMessage(projected)
            if message.role == .user, !historicalImages.isEmpty {
                result.append(ChatCompletionMessage(
                    role: "user", content: .multimodal(historicalImages + contentParts(completion.content))
                ))
                historicalImages.removeAll()
            } else {
                result.append(completion)
            }
        }
        // Only user content accepts image_url in the base Chat Completions contract.
        // Defer visual context until after tool-result blocks rather than interrupting a tool call.
        if !historicalImages.isEmpty {
            result.append(ChatCompletionMessage(role: "user", content: .multimodal(historicalImages)))
        }
        return result
    }

    private func contentParts(_ content: ChatCompletionMessage.Content) -> [ContentPart] {
        switch content {
        case .text(let text): text.isEmpty ? [] : [.text(text)]
        case .multimodal(let parts): parts
        case .none: []
        }
    }
}
