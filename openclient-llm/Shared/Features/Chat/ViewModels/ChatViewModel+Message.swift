//
//  ChatViewModel+Message.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

// MARK: - Message

extension ChatViewModel {
    struct SendMessageContext {
        let text: String
        let messages: [ChatMessage]
        let modelId: String
        let assistantId: UUID
        let systemPrompt: String
        let parameters: ModelParameters
        let webSearchEnabled: Bool
        let modelCapabilities: [LLMModel.Capability]
        let selectedModel: LLMModel
        let contextWindowTokens: Int?
        let contextSummary: String?
        let contextSummaryCursorMessageId: UUID?
    }

    func streamWithWebSearch(_ context: SendMessageContext) async {
        if context.selectedModel.mode == .imageGeneration {
            await performImageGeneration(context)
            return
        }
        let useAgentMode = context.modelCapabilities.contains(.functionCalling)
        if useAgentMode {
            await performAgentStreaming(context)
        } else {
            await performStreaming(context)
        }
    }

    func sendMessage() {
        guard case .loaded(var loadedState) = state else { return }
        guard !loadedState.isPreparingAttachment else { return }
        let text = loadedState.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !loadedState.pendingAttachments.isEmpty,
              let model = loadedState.selectedModel else { return }
        guard validateImageGenerationInput(
            text: text,
            attachments: loadedState.pendingAttachments,
            model: model
        ) else { return }

        if activeAssistantMessageId != nil {
            cancelActiveStreaming()
            guard case .loaded(var loadedState) = state else { return }
            let followUpText = loadedState.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !followUpText.isEmpty || !loadedState.pendingAttachments.isEmpty else { return }
            performSend(text: followUpText, model: model, loadedState: &loadedState)
        } else {
            performSend(text: text, model: model, loadedState: &loadedState)
        }
    }

    func prepareMessageState(text: String, model: LLMModel, loadedState: inout LoadedState) -> UUID {
        if loadedState.conversation == nil, !isPrivateChat {
            loadedState.conversation = Conversation(
                id: loadedState.pendingSessionId,
                modelId: model.id,
                systemPrompt: loadedState.systemPrompt,
                contextWindowTokens: loadedState.contextWindowTokens
            )
        }
        let userMessage = ChatMessage(role: .user, content: text, attachments: loadedState.pendingAttachments)
        loadedState.messages.append(userMessage)
        loadedState.inputText = ""
        loadedState.inputRevision += 1
        loadedState.pendingAttachments = []
        loadedState.isStreaming = true
        loadedState.errorMessage = nil
        let assistantMessage = ChatMessage(role: .assistant, content: "")
        loadedState.messages.append(assistantMessage)
        loadedState.responseRevision += 1
        refreshContextUsage(in: &loadedState)
        if loadedState.conversation?.title.isEmpty == true {
            loadedState.conversation?.title = text.isEmpty
                ? String(localized: "New Conversation")
                : String(text.prefix(50))
        }
        state = .loaded(loadedState)
        return assistantMessage.id
    }

    private func performSend(text: String, model: LLMModel, loadedState: inout LoadedState) {
        LogManager.info("sendMessage model=\(model.id) attachments=\(loadedState.pendingAttachments.count)")

        let assistantId = prepareMessageState(text: text, model: model, loadedState: &loadedState)
        let currentMessages = loadedState.messages.filter { $0.id != assistantId }
        let systemPrompt = loadedState.systemPrompt
        let parameters = loadedState.modelParameters
        let webSearchEnabled = loadedState.isWebSearchEnabled
        let modelCapabilities = model.capabilities
        let contextWindowTokens = loadedState.contextWindowTokens
        let contextSummary = loadedState.conversation?.contextSummary
        let contextSummaryCursorMessageId = loadedState.conversation?.contextSummaryCursorMessageId

        streamTask?.cancel()
        activeAssistantMessageId = assistantId
        beginStreamingBackground(for: assistantId)
        streamTask = Task {
            await streamWithWebSearch(SendMessageContext(
                text: text,
                messages: currentMessages,
                modelId: model.id,
                assistantId: assistantId,
                systemPrompt: systemPrompt,
                parameters: parameters,
                webSearchEnabled: webSearchEnabled,
                modelCapabilities: modelCapabilities,
                selectedModel: model,
                contextWindowTokens: contextWindowTokens,
                contextSummary: contextSummary,
                contextSummaryCursorMessageId: contextSummaryCursorMessageId
            ))
        }
    }
}
