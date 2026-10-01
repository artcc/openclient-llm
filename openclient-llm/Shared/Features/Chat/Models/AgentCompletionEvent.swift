//
//  AgentCompletionEvent.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 01/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

nonisolated enum AgentCompletionEvent: Sendable {
    case token(String)
    case reasoning(String)
    /// Invalidates provisional text; no further text or reasoning deltas are emitted for this round.
    case toolCallsDetected
    case completed(ChatCompletionResponse)
}
