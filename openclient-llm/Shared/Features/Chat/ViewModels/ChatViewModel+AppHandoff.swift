//
//  ChatViewModel+AppHandoff.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 29/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

// MARK: - App handoff

extension ChatViewModel {
    enum AppHandoffResult: Equatable {
        case newChat
        case conversation(Conversation)
        case draftPending
        case persistenceFailed
    }

    var canPrepareForAppHandoff: Bool {
        guard case .loaded(let loadedState) = state else { return false }
        return loadedState.inputText.isEmpty
            && loadedState.pendingAttachments.isEmpty
            && !loadedState.isPreparingAttachment
            && !loadedState.isRecording
            && !loadedState.isStartingRecording
            && !loadedState.isTranscribing
    }

    func prepareForAppHandoff() async -> AppHandoffResult {
        guard canPrepareForAppHandoff, case .loaded(let loadedState) = state else { return .draftPending }

        isPreparingAppHandoff = true
        defer { isPreparingAppHandoff = false }
        let activeAssistantId = activeAssistantMessageId
        cancelActiveStreaming(shouldPersist: false)
        removeEmptyAssistantMessage(id: activeAssistantId)
        guard loadedState.conversation != nil else {
            return .newChat
        }
        guard await persistConversation() else {
            if case .loaded(var currentState) = state {
                currentState.errorMessage = String(localized: "The conversation could not be saved.")
                state = .loaded(currentState)
            }
            return .persistenceFailed
        }
        guard case .loaded(let currentState) = state, let conversation = currentState.conversation else {
            return .persistenceFailed
        }
        return .conversation(conversation)
    }

    private func removeEmptyAssistantMessage(id: UUID?) {
        guard let id, case .loaded(var loadedState) = state,
              let index = loadedState.messages.firstIndex(where: { $0.id == id }) else { return }
        let message = loadedState.messages[index]
        let isEmpty = message.content.isEmpty
            && (message.reasoningContent?.isEmpty ?? true)
            && message.attachments.isEmpty
            && (message.webSearchResults?.isEmpty ?? true)
            && (message.toolCalls?.isEmpty ?? true)
            && message.toolCallId == nil
            && message.toolName == nil
        guard isEmpty else { return }
        loadedState.messages.remove(at: index)
        loadedState.responseRevision += 1
        refreshContextUsage(in: &loadedState)
        state = .loaded(loadedState)
    }
}
