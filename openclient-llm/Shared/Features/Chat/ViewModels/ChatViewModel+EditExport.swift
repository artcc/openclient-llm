//
//  ChatViewModel+EditExport.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 03/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

// MARK: - Phase 6: Export, Regenerate, Edit, Branch

extension ChatViewModel {
    func exportConversation() {
        guard case .loaded(var loadedState) = state,
              let conversation = loadedState.conversation else { return }

        do {
            let data = try exportConversationUseCase.execute(conversation)
            loadedState.exportedData = data
            state = .loaded(loadedState)
            LogManager.success("exportConversation id=\(conversation.id)")
        } catch {
            loadedState.errorMessage = error.localizedDescription
            state = .loaded(loadedState)
            LogManager.error("exportConversation failed: \(error)")
            scheduleErrorDismiss()
        }
    }

    func clearExportedData() {
        guard case .loaded(var loadedState) = state else { return }
        loadedState.exportedData = nil
        state = .loaded(loadedState)
    }

    func regenerateLastResponse() {
        guard case .loaded(var loadedState) = state,
              !loadedState.isStreaming,
              let model = loadedState.selectedModel else { return }

        guard loadedState.messages.last?.role == .assistant else { return }
        if model.mode == .imageGeneration {
            guard let userMessage = loadedState.messages.last(where: { $0.role == .user }),
                  validateImageGenerationInput(
                    text: userMessage.content,
                    attachments: userMessage.attachments,
                    model: model
                  ) else { return }
        }
        let previousAssistant = loadedState.messages.removeLast()
        guard !loadedState.messages.isEmpty else { return }
        let retainedImages = regenerationAttachments(
            previousAssistant: previousAssistant, model: model, messages: &loadedState.messages
        )
        invalidateCompactionIfNeeded(in: &loadedState, changedAt: loadedState.messages.count)

        loadedState.isStreaming = true
        loadedState.errorMessage = nil
        let assistantMessage = ChatMessage(role: .assistant, content: "", attachments: retainedImages)
        loadedState.messages.append(assistantMessage)
        loadedState.responseRevision += 1
        refreshContextUsage(in: &loadedState)
        state = .loaded(loadedState)

        let assistantMessageId = assistantMessage.id
        let currentMessages = loadedState.messages.filter { $0.id != assistantMessageId }
        LogManager.info("regenerateLastResponse model=\(model.id) messages=\(currentMessages.count)")
        streamTask?.cancel()
        activeAssistantMessageId = assistantMessageId
        beginStreamingBackground(for: assistantMessageId)
        streamTask = Task {
            await streamWithWebSearch(SendMessageContext(
                text: "",
                messages: currentMessages,
                modelId: model.id,
                assistantId: assistantMessageId,
                systemPrompt: loadedState.systemPrompt,
                parameters: loadedState.modelParameters,
                webSearchEnabled: loadedState.isWebSearchEnabled,
                modelCapabilities: model.capabilities,
                selectedModel: model,
                contextWindowTokens: loadedState.contextWindowTokens,
                contextSummary: loadedState.conversation?.contextSummary,
                contextSummaryCursorMessageId: loadedState.conversation?.contextSummaryCursorMessageId
            ))
        }
    }

    func editAndResend(id: UUID, newContent: String) {
        guard case .loaded(var loadedState) = state,
              !loadedState.isStreaming,
              let model = loadedState.selectedModel else { return }

        let trimmed = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Find the message index
        guard let messageIndex = loadedState.messages.firstIndex(where: { $0.id == id }),
              loadedState.messages[messageIndex].role == .user else { return }
        guard validateImageGenerationInput(
            text: trimmed,
            attachments: loadedState.messages[messageIndex].attachments,
            model: model
        ) else { return }

        // Update content and remove all messages after it (including previous assistant response)
        loadedState.messages[messageIndex].content = trimmed
        loadedState.messages = Array(loadedState.messages.prefix(messageIndex + 1))
        invalidateCompactionIfNeeded(in: &loadedState, changedAt: messageIndex)

        loadedState.isStreaming = true
        loadedState.errorMessage = nil

        let assistantMessage = ChatMessage(role: .assistant, content: "")
        loadedState.messages.append(assistantMessage)
        loadedState.responseRevision += 1
        refreshContextUsage(in: &loadedState)
        state = .loaded(loadedState)

        let assistantMessageId = assistantMessage.id
        let currentMessages = loadedState.messages.filter { $0.id != assistantMessageId }
        let systemPrompt = loadedState.systemPrompt
        let parameters = loadedState.modelParameters
        let webSearchEnabled = loadedState.isWebSearchEnabled
        let modelCapabilities = model.capabilities

        LogManager.info("editAndResend id=\(id) model=\(model.id)")
        streamTask?.cancel()
        activeAssistantMessageId = assistantMessageId
        beginStreamingBackground(for: assistantMessageId)
        streamTask = Task {
            await streamWithWebSearch(SendMessageContext(
                text: trimmed,
                messages: currentMessages,
                modelId: model.id,
                assistantId: assistantMessageId,
                systemPrompt: systemPrompt,
                parameters: parameters,
                webSearchEnabled: webSearchEnabled,
                modelCapabilities: modelCapabilities,
                selectedModel: model,
                contextWindowTokens: loadedState.contextWindowTokens,
                contextSummary: loadedState.conversation?.contextSummary,
                contextSummaryCursorMessageId: loadedState.conversation?.contextSummaryCursorMessageId
            ))
        }
    }

    func forkConversation(fromMessage messageId: UUID) {
        guard case .loaded(let loadedState) = state,
              let conversation = loadedState.conversation else { return }

        Task {
            do {
                let fork = try await branchConversationUseCase.execute(
                    conversation: conversation,
                    fromMessageId: messageId
                )
                guard case .loaded(var currentState) = state else { return }
                currentState.branchedConversation = fork
                state = .loaded(currentState)
                onForkCreated?(fork)
                LogManager.success("forkConversation fromMessage=\(messageId) newId=\(fork.id)")
            } catch {
                guard case .loaded(var currentState) = state else { return }
                currentState.errorMessage = error.localizedDescription
                state = .loaded(currentState)
                LogManager.error("forkConversation failed: \(error)")
                scheduleErrorDismiss()
            }
        }
    }

    func clearBranchedConversation() {
        guard case .loaded(var loadedState) = state else { return }
        loadedState.branchedConversation = nil
        state = .loaded(loadedState)
    }

    func handlePhase6Event(_ event: Event) {
        switch event {
        case .exportConversation:
            exportConversation()
        case .exportDataConsumed:
            clearExportedData()
        case .regenerateLastResponse:
            regenerateLastResponse()
        case .editMessage(let id, let newContent):
            editAndResend(id: id, newContent: newContent)
        case .forkFromMessage(let messageId):
            forkConversation(fromMessage: messageId)
        case .branchedConversationConsumed:
            clearBranchedConversation()
        case .toggleFavourite(let id):
            toggleFavourite(id)
        default:
            break
        }
    }

    func toggleFavourite(_ id: UUID) {
        guard case .loaded(var loadedState) = state,
              let index = loadedState.messages.firstIndex(where: { $0.id == id }) else { return }

        loadedState.messages[index].isFavourite.toggle()
        state = .loaded(loadedState)
        scheduleConversationPersistence()
        LogManager.debug("toggleFavourite id=\(id) isFavourite=\(loadedState.messages[index].isFavourite)")
    }

    func invalidateCompactionIfNeeded(in state: inout LoadedState, changedAt messageIndex: Int) {
        guard var conversation = state.conversation else { return }
        guard let cursorMessageId = conversation.contextSummaryCursorMessageId,
              let cursorIndex = state.messages.firstIndex(where: { $0.id == cursorMessageId }),
              cursorIndex < messageIndex else {
            conversation.contextSummary = nil
            conversation.contextSummaryCursorMessageId = nil
            state.conversation = conversation
            return
        }
    }
}

// MARK: - Private

private extension ChatViewModel {
    func regenerationAttachments(
        previousAssistant: ChatMessage,
        model: LLMModel,
        messages: inout [ChatMessage]
    ) -> [ChatMessage.Attachment] {
        guard let userIndex = messages.lastIndex(where: { $0.role == .user }),
              messages[userIndex...].contains(where: {
                  $0.role == .tool && $0.toolName == "generate_image"
              }) else { return [] }

        if model.supportsNativeImageGeneration {
            // Native regeneration restarts the turn instead of reusing completed tool generation.
            messages = Array(messages.prefix(userIndex + 1))
            return []
        }
        return previousAssistant.attachments.filter { $0.type == .image }
    }
}
