//
//  ChatViewModel+Interruption.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 21/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

extension ChatViewModel {
    func retryInterruptedResponse(_ messageId: UUID) {
        guard case .loaded(let loadedState) = state,
              loadedState.canRetryInterruptedResponse,
              activeAssistantMessageId == nil,
              let message = loadedState.messages.last,
              message.id == messageId, message.isInterruptedResponse else { return }

        // Regeneration preserves completed tool transcripts and per-turn image reservations.
        regenerateLastResponse()
    }
}
