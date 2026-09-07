//
//  ChatViewModel+Streaming.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 05/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

// MARK: - Streaming helpers

extension ChatViewModel {
    func performStreaming(_ sendContext: SendMessageContext) async {
        let assistantMessageId = sendContext.assistantId
        streamingBackgroundUseCase.update(.thinking)
        LogManager.debug("performStreaming model=\(sendContext.modelId) messages=\(sendContext.messages.count)")
        do {
            let requestContext = try await prepareRequestContext(
                for: sendContext,
                systemPrompt: sendContext.systemPrompt,
                tools: []
            )
            var allMessages = requestContext.messages
            if !requestContext.effectiveSystemPrompt.isEmpty {
                allMessages.insert(ChatMessage(role: .system, content: requestContext.effectiveSystemPrompt), at: 0)
            }
            let stream = streamMessageUseCase.execute(
                messages: allMessages,
                model: sendContext.modelId,
                parameters: parametersCappedToModelOutput(
                    sendContext.parameters, model: sendContext.selectedModel
                )
            )
            var reportedPromptTokens: Int?
            for try await chunk in stream {
                if case .usage(let usage) = chunk, usage.promptTokens > 0 {
                    reportedPromptTokens = usage.promptTokens
                }
                guard !Task.isCancelled,
                      isActiveStream(assistantMessageId),
                      await processStreamingChunk(chunk, assistantMessageId: assistantMessageId) else { return }
            }

            await finishStreaming(
                assistantMessageId,
                model: sendContext.modelId,
                reportedPromptTokens: reportedPromptTokens
            )
        } catch is CancellationError {
            if isActiveStream(assistantMessageId) { cancelActiveStreaming() }
        } catch {
            await handleStreamingFailure(error, assistantMessageId: assistantMessageId, model: sendContext.modelId)
        }
    }

    func applyStreamChunk(_ chunk: StreamChunk, to state: inout LoadedState, assistantMessageId: UUID) {
        switch chunk {
        case .token(let token):
            if let index = state.messages.firstIndex(where: { $0.id == assistantMessageId }) {
                state.messages[index].content += token
            }
        case .reasoning(let text):
            if let index = state.messages.firstIndex(where: { $0.id == assistantMessageId }) {
                state.messages[index].reasoningContent = (state.messages[index].reasoningContent ?? "") + text
            }
        case .usage(let usage):
            if let index = state.messages.firstIndex(where: { $0.id == assistantMessageId }) {
                state.messages[index].tokenUsage = usage
            }
            if usage.promptTokens > 0 {
                refreshContextUsage(in: &state, calibratedPromptTokens: usage.promptTokens)
            }
        case .image(let imageData):
            appendGeneratedImage(imageData, to: &state, assistantMessageId: assistantMessageId)
        }
    }

}

// MARK: - Private

private extension ChatViewModel {
    func handleStreamingFailure(_ error: Error, assistantMessageId: UUID, model: String) async {
        guard !Task.isCancelled, isActiveStream(assistantMessageId) else { return }
        flushStreamingTextUpdates(for: assistantMessageId)
        guard case .loaded(var currentState) = state else { return }
        LogManager.error("performStreaming error model=\(model): \(error)")
        if let index = currentState.messages.firstIndex(where: { $0.id == assistantMessageId }),
           currentState.messages[index].content.isEmpty,
           (currentState.messages[index].reasoningContent ?? "").isEmpty,
           currentState.messages[index].attachments.isEmpty {
            currentState.messages.remove(at: index)
        }
        currentState.isStreaming = false
        currentState.errorMessage = error.localizedDescription
        refreshContextUsage(in: &currentState)
        state = .loaded(currentState)
        scheduleErrorDismiss()
        streamingBackgroundUseCase.update(.saving)
        await persistConversation()
        guard !Task.isCancelled, isActiveStream(assistantMessageId) else { return }
        streamingBackgroundUseCase.end(success: false)
        completeActiveStream(assistantMessageId)
    }

    func processStreamingChunk(_ chunk: StreamChunk, assistantMessageId: UUID) async -> Bool {
        switch chunk {
        case .token(let text):
            streamingBackgroundUseCase.update(.responding)
            let didPublish = enqueueStreamingTextUpdate(.token(text), assistantMessageId: assistantMessageId)
            if didPublish { await Task.yield() }
        case .reasoning(let text):
            streamingBackgroundUseCase.update(.thinking)
            let didPublish = enqueueStreamingTextUpdate(.reasoning(text), assistantMessageId: assistantMessageId)
            if didPublish { await Task.yield() }
        default:
            guard case .loaded(var currentState) = state else { return false }
            if !streamingUpdateBuffer.updates.isEmpty {
                let updates = takeStreamingTextUpdates(for: assistantMessageId)
                applyStreamingTextUpdates(updates, to: &currentState, assistantMessageId: assistantMessageId)
            }
            applyStreamChunk(chunk, to: &currentState, assistantMessageId: assistantMessageId)
            state = .loaded(currentState)
        }
        return true
    }

    func finishStreaming(
        _ assistantMessageId: UUID,
        model: String,
        reportedPromptTokens: Int?
    ) async {
        guard isActiveStream(assistantMessageId), case .loaded(var currentState) = state else { return }
        let updates = takeStreamingTextUpdates(for: assistantMessageId)
        applyStreamingTextUpdates(updates, to: &currentState, assistantMessageId: assistantMessageId)
        currentState.isStreaming = false
        removeEmptyAssistantMessage(assistantMessageId, from: &currentState)
        refreshContextUsage(
            in: &currentState,
            calibratedPromptTokens: contextTokensAfterResponse(
                promptTokens: reportedPromptTokens,
                assistantMessageId: assistantMessageId,
                state: currentState
            )
        )
        state = .loaded(currentState)
        LogManager.success("performStreaming completed model=\(model)")
        streamingBackgroundUseCase.update(.saving)
        let didPersist = await persistConversation()
        guard !Task.isCancelled, isActiveStream(assistantMessageId) else { return }
        let didComplete = isPrivateChat || didPersist
        if didComplete {
            if streamingBackgroundUseCase.shouldSendCompletionNotification {
                notifyStreamingCompletedUseCase.execute()
            }
        } else {
            scheduleConversationPersistence()
        }
        streamingBackgroundUseCase.end(success: didComplete)
        completeActiveStream(assistantMessageId)
    }

    func removeEmptyAssistantMessage(_ assistantMessageId: UUID, from state: inout LoadedState) {
        guard let index = state.messages.firstIndex(where: { $0.id == assistantMessageId }),
              state.messages[index].content.isEmpty,
              (state.messages[index].reasoningContent ?? "").isEmpty,
              state.messages[index].attachments.isEmpty else { return }
        state.messages.remove(at: index)
        state.errorMessage = String(localized: "The model returned an empty response. Please try again.")
    }

    func appendGeneratedImage(
        _ data: Data,
        to state: inout LoadedState,
        assistantMessageId: UUID
    ) {
        guard let index = state.messages.firstIndex(where: { $0.id == assistantMessageId }),
              let attachment = generatedImageAttachment(data: data, state: state) else { return }
        state.messages[index].attachments.append(attachment)
    }

}
