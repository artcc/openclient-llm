//
//  ImageOperationAttempt.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 01/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

/// Resolves the latest user turn, including legacy and partially delivered tool transcripts.
nonisolated struct ImageOperationAttempt {
    let operation: ChatMessage.ImageOperation?

    var wasAttempted: Bool { operation != nil }
    var preventsNativeRestart: Bool { wasAttempted && operation != .generation }

    init(messages: [ChatMessage]) {
        guard let userIndex = messages.lastIndex(where: { $0.role == .user }) else {
            operation = nil
            return
        }
        let user = messages[userIndex]
        let turn = messages.suffix(from: userIndex + 1)
        let calls = turn.filter { $0.role == .assistant }.flatMap { $0.toolCalls ?? [] }
        let namesById = Dictionary(grouping: calls, by: \.id).mapValues { Set($0.map(\.function.name)) }
        var evidence = Set<ChatMessage.ImageOperation>()
        if let reserved = user.imageOperationAttempted { evidence.insert(reserved) }
        for result in turn where result.role == .tool {
            let names = result.toolCallId.flatMap { namesById[$0] } ?? []
            let name = result.toolName ?? (names.count == 1 ? names.first : nil)
            if let kind = Self.operation(for: name) { evidence.insert(kind) }
        }
        // An edit call must never be reinterpreted as native generation, even if its result is missing.
        if calls.contains(where: { $0.function.name == "edit_image" }) { evidence.insert(.editing) }
        if evidence.contains(.editing) {
            operation = .editing
        } else if evidence.contains(.unknown) {
            operation = .unknown
        } else if evidence.contains(.generation) {
            operation = .generation
        } else if user.imageGenerationAttempted == true || calls.contains(where: {
            Self.operation(for: $0.function.name) != nil
        }) {
            operation = .unknown
        } else {
            operation = nil
        }
    }

    private static func operation(for name: String?) -> ChatMessage.ImageOperation? {
        switch name {
        case "generate_image": .generation
        case "edit_image": .editing
        default: nil
        }
    }
}
