//
//  ChatViewModel+Helpers.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 01/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

enum ChatContextError: LocalizedError {
    case latestTurnExceedsContextWindow
    case automaticCompactionFailed

    var errorDescription: String? {
        switch self {
        case .latestTurnExceedsContextWindow:
            String(localized: """
            The latest message and its attachments exceed this context window. \
            Increase the context window or shorten the message.
            """)
        case .automaticCompactionFailed:
            String(localized: "The earlier conversation context could not be preserved. Please try again.")
        }
    }
}

struct RequestContextConfiguration {
    let selectedModel: LLMModel?
    let contextWindowTokens: Int?
    let summary: String?
    let summaryCursorMessageId: UUID?
    let tools: [ToolDefinition]
}

// MARK: - Internal helpers

extension ChatViewModel {
    func updateInput(_ text: String) {
        guard case .loaded(var loadedState) = state else { return }
        loadedState.inputText = text
        loadedState.inputRevision += 1
        state = .loaded(loadedState)
    }

    func handleSuggestionTapped(_ prompt: String) {
        updateInput(prompt)
        sendMessage()
    }

    func updateContextWindow(_ tokens: Int?) {
        guard case .loaded(var loadedState) = state else { return }
        let normalizedTokens = tokens.flatMap { $0 > 0 ? $0 : nil }
        loadedState.contextWindowTokens = normalizedTokens
        loadedState.conversation?.contextWindowTokens = normalizedTokens
        refreshContextUsage(in: &loadedState)
        state = .loaded(loadedState)
        scheduleConversationPersistence()
    }

    func isActiveStream(_ assistantMessageId: UUID) -> Bool {
        activeAssistantMessageId == assistantMessageId
    }

    func completeActiveStream(_ assistantMessageId: UUID) {
        guard isActiveStream(assistantMessageId) else { return }
        stopBackgroundPersistenceCheckpoints()
        resetStreamingTextUpdates()
        activeAssistantMessageId = nil
        streamTask = nil
    }

    func buildEffectiveSystemPrompt(
        profileContext: String,
        memoryContext: String,
        conversationSystemPrompt: String
    ) -> String {
        let profile = profileContext.trimmingCharacters(in: .whitespacesAndNewlines)
        let memory = memoryContext.trimmingCharacters(in: .whitespacesAndNewlines)
        let conversation = conversationSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        var parts: [String] = []

        if !profile.isEmpty {
            parts.append("""
            The following is background information about the user. \
            Use it only to personalize your responses when relevant — \
            do not mention it proactively or make it the topic of conversation.
            \(profile)
            """)
        }

        if !memory.isEmpty {
            parts.append("""
            The following are facts you know about the user from previous conversations. \
            Use them only when directly relevant to what the user is asking — \
            never bring them up unprompted.
            \(memory)
            """)
        }

        if !conversation.isEmpty {
            parts.append(conversation)
        }

        return parts.joined(separator: "\n\n")
    }

    func refreshContextUsage(in loadedState: inout LoadedState, calibratedPromptTokens: Int? = nil) {
        let profileContext = isPrivateChat ? "" : getUserProfileContextUseCase?.execute() ?? ""
        let memoryContext = isPrivateChat ? "" : getMemoryContextUseCase?.execute() ?? ""
        let requestPrompt = requestSystemPrompt(
            loadedState.systemPrompt,
            modelCapabilities: loadedState.selectedModel?.capabilities ?? [],
            webSearchEnabled: loadedState.isWebSearchEnabled
        )
        let systemPrompt = buildEffectiveSystemPrompt(
            profileContext: profileContext,
            memoryContext: memoryContext,
            conversationSystemPrompt: requestPrompt
        )
        let partition = contextPartition(
            messages: loadedState.messages,
            summary: loadedState.conversation?.contextSummary,
            cursorMessageId: loadedState.conversation?.contextSummaryCursorMessageId
        )
        let tools = contextTools(for: loadedState)
        let messages = loadedState.selectedModel.map {
            ImageAttachmentContext.messagesForModel(partition.messages, model: $0)
        } ?? partition.messages
        loadedState.contextUsage = ContextWindowBuilder().usage(
            messages: messages,
            systemPrompt: systemPrompt,
            summary: loadedState.conversation?.contextSummary,
            model: modelWithContextWindow(
                loadedState.selectedModel,
                override: loadedState.contextWindowTokens
            ),
            tools: tools,
            compactedMessageCount: partition.compactedCount,
            calibratedPromptTokens: calibratedPromptTokens
        )
    }

    func contextTokensAfterResponse(
        promptTokens: Int?,
        assistantMessageId: UUID,
        state: LoadedState
    ) -> Int? {
        guard let promptTokens else { return nil }
        guard let assistant = state.messages.first(where: { $0.id == assistantMessageId }) else { return promptTokens }
        let messages = state.selectedModel.map {
            ImageAttachmentContext.messagesForModel([assistant], model: $0)
        } ?? [assistant]
        let responseTokens = ContextWindowBuilder().estimatedInputTokens(messages: messages, systemPrompt: "")
        return promptTokens + responseTokens
    }

    func buildRequestContext(
        messages: [ChatMessage],
        systemPrompt: String,
        configuration: RequestContextConfiguration
    ) throws -> ContextWindowBuilder.Context {
        let profileContext = isPrivateChat ? "" : getUserProfileContextUseCase?.execute() ?? ""
        let memoryContext = isPrivateChat ? "" : getMemoryContextUseCase?.execute() ?? ""
        let effectiveSystemPrompt = buildEffectiveSystemPrompt(
            profileContext: profileContext,
            memoryContext: memoryContext,
            conversationSystemPrompt: systemPrompt
        )
        let partition = contextPartition(
            messages: messages,
            summary: configuration.summary,
            cursorMessageId: configuration.summaryCursorMessageId
        )
        let projectedMessages = configuration.selectedModel.map {
            ImageAttachmentContext.messagesForModel(partition.messages, model: $0)
        } ?? partition.messages
        let context = ContextWindowBuilder().build(
            messages: projectedMessages,
            systemPrompt: effectiveSystemPrompt,
            summary: configuration.summary,
            model: modelWithContextWindow(
                configuration.selectedModel,
                override: configuration.contextWindowTokens
            ),
            tools: configuration.tools,
            compactedMessageCount: partition.compactedCount
        )
        guard !context.isLatestTurnOverBudget else { throw ChatContextError.latestTurnExceedsContextWindow }
        return context
    }

    func parametersCappedToModelOutput(_ parameters: ModelParameters, model: LLMModel?) -> ModelParameters {
        guard let maxOutputTokens = model?.maxOutputTokens,
              let requestedMaxTokens = parameters.maxTokens else { return parameters }
        return ModelParameters(
            temperature: parameters.temperature,
            maxTokens: min(requestedMaxTokens, maxOutputTokens),
            topP: parameters.topP
        )
    }

    @discardableResult
    func persistConversation() async -> Bool {
        guard let snapshot = conversationForPersistence() else { return false }
        return await enqueuePersistence(of: snapshot).value.didPersist
    }

    @discardableResult
    func scheduleConversationPersistence() -> Task<PersistenceResult, Never>? {
        guard let snapshot = conversationForPersistence() else { return nil }
        return enqueuePersistence(of: snapshot)
    }

    private func conversationForPersistence() -> (conversation: Conversation, expectedBase: Conversation?)? {
        guard !isPrivateChat else { return nil }
        guard case .loaded(var loadedState) = state,
              var conversation = loadedState.conversation else { return nil }
        let expectedBase = queuedPersistenceConversation?.id == conversation.id
            ? queuedPersistenceConversation
            : persistenceBase

        conversation.messages = loadedState.messages
        conversation.systemPrompt = loadedState.systemPrompt
        conversation.modelParameters = loadedState.modelParameters
        conversation.contextWindowTokens = loadedState.contextWindowTokens
        conversation.updatedAt = Date()
        if let model = loadedState.selectedModel {
            conversation.modelId = model.id
        }
        loadedState.conversation = conversation
        state = .loaded(loadedState)
        return (conversation, expectedBase)
    }

    @discardableResult
    private func enqueuePersistence(
        of snapshot: (conversation: Conversation, expectedBase: Conversation?)
    ) -> Task<PersistenceResult, Never> {
        let previousTask = persistenceTask
        persistenceGeneration += 1
        let generation = persistenceGeneration
        let resetGeneration = persistenceResetGeneration
        queuedPersistenceConversation = snapshot.conversation
        let task = Task { [weak self] in
            let previousResult = await withTaskCancellationHandler {
                await previousTask?.value
            } onCancel: {
                previousTask?.cancel()
            }
            guard !Task.isCancelled, let self,
                  resetGeneration == persistenceResetGeneration else {
                return PersistenceResult(didPersist: false, durableConversation: nil)
            }
            return await persistSnapshot(
                snapshot,
                previousResult: previousResult,
                generation: generation,
                resetGeneration: resetGeneration
            )
        }
        persistenceTask = task
        return task
    }

    private func persistSnapshot(
        _ snapshot: (conversation: Conversation, expectedBase: Conversation?),
        previousResult: PersistenceResult?,
        generation: Int,
        resetGeneration: Int
    ) async -> PersistenceResult {
        do {
            let durableBase = previousResult?.durableConversation?.id == snapshot.conversation.id
                ? previousResult?.durableConversation
                : persistenceBase?.id == snapshot.conversation.id
                    ? persistenceBase
                    : snapshot.expectedBase
            let submittedConversation: Conversation
            if let localBase = snapshot.expectedBase, let durableBase, localBase != durableBase {
                submittedConversation = try rebasePersistenceConversation(
                    snapshot.conversation,
                    base: localBase,
                    onto: durableBase
                )
            } else {
                submittedConversation = snapshot.conversation
            }
            let persisted = try await saveConversationUseCase.execute(
                submittedConversation,
                expectedBase: durableBase
            )
            guard !Task.isCancelled, resetGeneration == persistenceResetGeneration else {
                return PersistenceResult(didPersist: false, durableConversation: nil)
            }
            applyPersistedConversation(persisted, submittedConversation: submittedConversation)
            NotificationCenter.default.post(name: .conversationDidUpdate, object: nil)
            onConversationUpdated?()
            finishPersistenceIfCurrent(generation)
            return PersistenceResult(didPersist: true, durableConversation: persisted)
        } catch {
            LogManager.error("persistConversation failed: \(error)")
            finishPersistenceIfCurrent(generation)
            return PersistenceResult(didPersist: false, durableConversation: nil)
        }
    }

    private func finishPersistenceIfCurrent(_ generation: Int) {
        guard generation == persistenceGeneration else { return }
        queuedPersistenceConversation = nil
        persistenceTask = nil
    }

    func applyPersistedConversation(
        _ persistedConversation: Conversation,
        submittedConversation: Conversation
    ) {
        guard case .loaded(var loadedState) = state,
              loadedState.conversation?.id == persistedConversation.id else { return }
        persistenceBase = persistedConversation
        var desiredConversation = loadedState.conversation ?? submittedConversation
        desiredConversation.messages = loadedState.messages
        desiredConversation.systemPrompt = loadedState.systemPrompt
        desiredConversation.modelParameters = loadedState.modelParameters
        desiredConversation.contextWindowTokens = loadedState.contextWindowTokens
        if let selectedModel = loadedState.selectedModel {
            desiredConversation.modelId = selectedModel.id
        }
        guard var mergedConversation = try? rebasePersistenceConversation(
            desiredConversation,
            base: submittedConversation,
            onto: persistedConversation
        ) else {
            return
        }
        mergedConversation.updatedAt = max(desiredConversation.updatedAt, persistedConversation.updatedAt)
        let hasSameRequestMessages = mergedConversation.messages.elementsEqual(loadedState.messages) {
            $0.hasSameRequestContent(as: $1)
        }
        let retainsContextUsage = hasSameRequestMessages
            && mergedConversation.systemPrompt == loadedState.systemPrompt
            && mergedConversation.contextWindowTokens == loadedState.contextWindowTokens
            && mergedConversation.modelId == loadedState.selectedModel?.id
            && mergedConversation.contextSummary == loadedState.conversation?.contextSummary
            && mergedConversation.contextSummaryCursorMessageId
                == loadedState.conversation?.contextSummaryCursorMessageId
        let contextUsage = loadedState.contextUsage
        loadedState.conversation = mergedConversation
        loadedState.messages = mergedConversation.messages
        loadedState.systemPrompt = mergedConversation.systemPrompt
        loadedState.modelParameters = mergedConversation.modelParameters
        loadedState.contextWindowTokens = mergedConversation.contextWindowTokens
        if let model = loadedState.availableModels.first(where: { $0.id == mergedConversation.modelId }) {
            loadedState.selectedModel = model
        }
        if retainsContextUsage {
            loadedState.contextUsage = contextUsage
        } else {
            refreshContextUsage(in: &loadedState)
        }
        state = .loaded(loadedState)
    }

    func rebasePersistenceConversation(
        _ incoming: Conversation,
        base: Conversation,
        onto current: Conversation
    ) throws -> Conversation {
        var normalizedIncoming = incoming
        var normalizedBase = base
        var normalizedCurrent = current
        for baseIndex in normalizedBase.messages.indices {
            let baseMessage = normalizedBase.messages[baseIndex]
            guard let incomingIndex = normalizedIncoming.messages.firstIndex(where: { $0.id == baseMessage.id }),
                  let currentIndex = normalizedCurrent.messages.firstIndex(where: { $0.id == baseMessage.id }) else {
                continue
            }
            let incomingMessage = normalizedIncoming.messages[incomingIndex]
            let currentMessage = normalizedCurrent.messages[currentIndex]
            if incomingMessage != baseMessage {
                normalizedCurrent.messages[currentIndex] = incomingMessage
                normalizedBase.messages[baseIndex] = incomingMessage
            } else if currentMessage != baseMessage {
                normalizedBase.messages[baseIndex] = currentMessage
                normalizedIncoming.messages[incomingIndex] = currentMessage
            }
        }
        var rebased = try ConversationRebaser.rebase(
            normalizedIncoming,
            base: normalizedBase,
            onto: normalizedCurrent
        )
        rebased.updatedAt = max(incoming.updatedAt, current.updatedAt)
        return rebased
    }

    func modelWithContextWindow(_ model: LLMModel?, override contextWindowTokens: Int?) -> LLMModel? {
        guard var model else { return nil }
        if let contextWindowTokens, contextWindowTokens > 0 {
            model.maxInputTokens = contextWindowTokens
        }
        return model
    }

    func contextPartition(
        messages: [ChatMessage],
        summary: String?,
        cursorMessageId: UUID?
    ) -> (messages: [ChatMessage], compactedCount: Int) {
        guard summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              let cursorMessageId,
              let cursorIndex = messages.firstIndex(where: { $0.id == cursorMessageId }) else {
            return (messages, 0)
        }
        return (Array(messages.dropFirst(cursorIndex + 1)), cursorIndex + 1)
    }

    func contextTools(for loadedState: LoadedState) -> [ToolDefinition] {
        agentToolDefinitions(for: loadedState)
    }

    func generatedImageAttachment(
        data: Data,
        mimeType: String? = nil,
        state _: LoadedState
    ) -> ChatMessage.Attachment? {
        ChatMessage.Attachment(
            type: .image,
            fileName: String(localized: "Generated Image"),
            mimeType: mimeType ?? (try? GeneratedImageDecoder.decode(data: data).mimeType) ?? "image/png",
            fileRelativePath: "",
            transientData: data
        )
    }

    func scheduleErrorDismiss() {
        errorDismissTask?.cancel()
        errorDismissTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, case .loaded(var currentState) = state else { return }
            currentState.errorMessage = nil
            state = .loaded(currentState)
        }
    }

}
