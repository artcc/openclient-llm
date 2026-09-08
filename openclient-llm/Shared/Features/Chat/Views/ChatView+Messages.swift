//
//  ChatView+Messages.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 14/07/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

extension ChatView {
    // MARK: - Messages List

    func messagesList(_ state: ChatMessageListState) -> some View {
        let tipMessageId = state.messages.last {
            $0.role == .assistant && !$0.content.isEmpty
        }?.id
        let lastMessageId = state.messages.last?.id

        // LazyVStack can fail to converge when upward scrolling overlaps live message layout updates.
        return VStack(spacing: 24) {
            ForEach(state.messages) { message in
                let isLast = message.id == lastMessageId
                let isStreamingMsg = state.isStreaming && isLast
                if shouldRenderMessage(message, isStreaming: isStreamingMsg) {
                    MessageBubbleView(
                        message: message,
                        isStreaming: isStreamingMsg,
                        isSpeaking: state.speakingMessageId == message.id,
                        hasTTS: state.hasTTS,
                        showTokenUsage: state.showTokenUsage,
                        isLastMessage: isLast,
                        isRunningTool: isLast && state.isRunningTool,
                        showsMessageActionsTip: message.id == tipMessageId && !state.isStreaming,
                        onSpeakTapped: { viewModel.send(.speakMessageTapped(message)) },
                        onStopSpeakingTapped: { viewModel.send(.stopSpeakingTapped) },
                        onEditTapped: message.role == .user ? {
                            editingMessage = message
                            editingMessageText = message.content
                        } : nil,
                        onRegenerateTapped: (message.role == .assistant && isLast) ? {
                            viewModel.send(.regenerateLastResponse)
                        } : nil,
                        onForkTapped: state.canFork ? {
                            viewModel.send(.forkFromMessage(message.id))
                        } : nil,
                        onFavouriteTapped: { viewModel.send(.toggleFavourite(message.id)) },
                        onLayoutChanged: isLast ? { renderedMessageRevision += 1 } : nil
                    )
                    .id(message.id)
                    .transition(.opacity)
                }
            }
        }
        .scrollTargetLayout()
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
        .frame(maxWidth: 800)
        .frame(maxWidth: .infinity)
    }

    func shouldRenderMessage(_ message: ChatMessage, isStreaming: Bool) -> Bool {
        let isEmptyAssistant = message.role == .assistant
            && message.content.isEmpty
            && (message.reasoningContent ?? "").isEmpty
            && message.attachments.isEmpty
        return !isEmptyAssistant || isStreaming
    }

    func handleSend(_ text: String) {
        viewModel.send(.inputChanged(text))
        viewModel.send(.sendTapped)
        showActions = false
    }

    // MARK: - Scroll Navigation

    func scrollAnchorButton(isTop: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isTop ? "chevron.up" : "chevron.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 44, height: 44)
                .glassEffect(.regular, in: .circle)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 16)
        .padding(isTop ? .top : .bottom, 16)
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }

}
