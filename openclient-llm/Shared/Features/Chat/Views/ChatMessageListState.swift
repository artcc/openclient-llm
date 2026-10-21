//
//  ChatMessageListState.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 21/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

struct ChatMessageListState: Equatable {
    let messages: [ChatMessage]
    let selectedModel: LLMModel?
    let conversationStarters: [ConversationStarter]
    let isStreaming: Bool
    let speakingMessageId: UUID?
    let hasTTS: Bool
    let showTokenUsage: Bool
    let isRunningTool: Bool
    let canFork: Bool
    let canRetryInterruptedResponse: Bool
    let scrollSnapshot: ChatScrollState.Snapshot

    init(loadedState: ChatViewModel.LoadedState) {
        let lastMessageId = loadedState.messages.last?.id
        messages = loadedState.messages.filter { message in
            guard message.role != .tool else { return false }
            guard message.role != .assistant || (message.toolCalls?.isEmpty ?? true) else { return false }
            let isEmptyAssistant = message.role == .assistant
                && message.content.isEmpty
                && (message.reasoningContent ?? "").isEmpty
                && message.attachments.isEmpty
            return !isEmptyAssistant || message.isInterruptedResponse
                || (loadedState.isStreaming && message.id == lastMessageId)
        }
        selectedModel = loadedState.selectedModel
        conversationStarters = loadedState.conversationStarters
        isStreaming = loadedState.isStreaming
        speakingMessageId = loadedState.speakingMessageId
        hasTTS = loadedState.ttsModelId != nil
        showTokenUsage = loadedState.showTokenUsage
        isRunningTool = !loadedState.activeToolCallIds.isEmpty
        canFork = loadedState.conversation != nil
        canRetryInterruptedResponse = loadedState.canRetryInterruptedResponse
        scrollSnapshot = ChatScrollState.Snapshot(loadedState: loadedState)
    }
}
