//
//  ChatViewModel+Compaction.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 26/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

struct PendingPreflightCompaction {
    let assistantMessageId: UUID
    let previousSummary: String?
    let previousCursorMessageId: UUID?
    let attemptedSummary: String
    let attemptedCursorMessageId: UUID
}

// MARK: - Compaction

extension ChatViewModel {
    func prepareRequestContext(
        for sendContext: SendMessageContext,
        systemPrompt: String,
        tools: [ToolDefinition]
    ) async throws -> ContextWindowBuilder.Context {
        var summary = sendContext.contextSummary
        var cursorMessageId = sendContext.contextSummaryCursorMessageId
        var requestContext = try makeRequestContext(
            sendContext,
            systemPrompt: systemPrompt,
            tools: tools,
            summary: summary,
            cursorMessageId: cursorMessageId
        )
        guard !isPrivateChat,
              (sendContext.contextWindowTokens ?? sendContext.selectedModel.maxInputTokens ?? 0) > 0 else {
            return requestContext
        }

        while !requestContext.excludedMessages.isEmpty {
            let compacted = try await compactBeforeSending(
                sendContext,
                systemPrompt: systemPrompt,
                tools: tools,
                summary: summary,
                cursorMessageId: cursorMessageId
            )
            summary = compacted.summary
            cursorMessageId = compacted.cursorMessageId
            requestContext = try makeRequestContext(
                sendContext,
                systemPrompt: systemPrompt,
                tools: tools,
                summary: summary,
                cursorMessageId: cursorMessageId
            )
        }
        return requestContext
    }

    func rollbackPendingPreflightCompaction(for assistantMessageId: UUID) {
        guard let pending = pendingPreflightCompaction,
              pending.assistantMessageId == assistantMessageId else { return }
        rollbackPreflightCompaction(pending)
    }
}

// MARK: - Private

private extension ChatViewModel {
    func makeRequestContext(
        _ sendContext: SendMessageContext,
        systemPrompt: String,
        tools: [ToolDefinition],
        summary: String?,
        cursorMessageId: UUID?
    ) throws -> ContextWindowBuilder.Context {
        try buildRequestContext(
            messages: sendContext.messages,
            systemPrompt: systemPrompt,
            configuration: RequestContextConfiguration(
                selectedModel: sendContext.selectedModel,
                contextWindowTokens: sendContext.contextWindowTokens,
                summary: summary,
                summaryCursorMessageId: cursorMessageId,
                tools: tools
            )
        )
    }

    func compactBeforeSending(
        _ sendContext: SendMessageContext,
        systemPrompt: String,
        tools: [ToolDefinition],
        summary: String?,
        cursorMessageId: UUID?
    ) async throws -> CompactedConversation {
        try Task.checkCancellation()
        guard isActiveStream(sendContext.assistantId) else { throw CancellationError() }
        let configuration = makeCompactionConfiguration(
            summary: (summary, cursorMessageId),
            model: sendContext.selectedModel,
            contextWindowTokens: sendContext.contextWindowTokens,
            systemPrompt: systemPrompt,
            tools: tools
        )
        guard let compacted = try await compactConversationUseCase.execute(
            messages: ImageAttachmentContext.messagesForModel(sendContext.messages, model: sendContext.selectedModel),
            configuration: configuration
        ), compactionCursorAdvanced(
            from: cursorMessageId,
            to: compacted.cursorMessageId,
            in: sendContext.messages
        ) else {
            throw ChatContextError.automaticCompactionFailed
        }
        try Task.checkCancellation()
        try await persistPreflightCompaction(
            compacted,
            expectedSummary: summary,
            expectedCursorMessageId: cursorMessageId,
            sendContext: sendContext
        )
        return compacted
    }

    func makeCompactionConfiguration(
        summary: (text: String?, cursorMessageId: UUID?),
        model: LLMModel,
        contextWindowTokens: Int?,
        systemPrompt: String,
        tools: [ToolDefinition]
    ) -> CompactionConfiguration {
        let effectiveSystemPrompt = buildEffectiveSystemPrompt(
            profileContext: getUserProfileContextUseCase?.execute() ?? "",
            memoryContext: getMemoryContextUseCase?.execute() ?? "",
            conversationSystemPrompt: systemPrompt
        )
        return CompactionConfiguration(
            existingSummary: summary.text,
            summaryCursorMessageId: summary.cursorMessageId,
            model: model.id,
            contextWindowTokens: contextWindowTokens ?? model.maxInputTokens,
            maxOutputTokens: model.maxOutputTokens,
            systemPrompt: effectiveSystemPrompt,
            tools: tools
        )
    }

    func compactionCursorAdvanced(
        from currentCursorMessageId: UUID?,
        to newCursorMessageId: UUID,
        in messages: [ChatMessage]
    ) -> Bool {
        guard let newIndex = messages.firstIndex(where: { $0.id == newCursorMessageId }) else { return false }
        guard let currentCursorMessageId else { return true }
        guard let currentIndex = messages.firstIndex(where: { $0.id == currentCursorMessageId }) else { return false }
        return newIndex > currentIndex
    }

    func persistPreflightCompaction(
        _ compacted: CompactedConversation,
        expectedSummary: String?,
        expectedCursorMessageId: UUID?,
        sendContext: SendMessageContext
    ) async throws {
        guard case .loaded(var currentState) = state,
              isActiveStream(sendContext.assistantId),
              currentState.selectedModel?.id == sendContext.modelId,
              currentState.contextWindowTokens == sendContext.contextWindowTokens,
              currentState.conversation?.contextSummary == expectedSummary,
              currentState.conversation?.contextSummaryCursorMessageId == expectedCursorMessageId,
              hasSameRequestMessages(currentState.messages, as: sendContext) else {
            throw CancellationError()
        }
        let pending = PendingPreflightCompaction(
            assistantMessageId: sendContext.assistantId,
            previousSummary: expectedSummary,
            previousCursorMessageId: expectedCursorMessageId,
            attemptedSummary: compacted.summary,
            attemptedCursorMessageId: compacted.cursorMessageId
        )
        pendingPreflightCompaction = pending
        currentState.conversation?.contextSummary = compacted.summary
        currentState.conversation?.contextSummaryCursorMessageId = compacted.cursorMessageId
        refreshContextUsage(in: &currentState)
        state = .loaded(currentState)
        let didPersist = await persistConversation()
        if !didPersist {
            rollbackPreflightCompaction(pending)
            try Task.checkCancellation()
            throw ChatContextError.automaticCompactionFailed
        }
        clearPendingPreflightCompaction(pending)
        try Task.checkCancellation()
        guard case .loaded(let persistedState) = state,
              isActiveStream(sendContext.assistantId),
              persistedState.selectedModel?.id == sendContext.modelId,
              persistedState.contextWindowTokens == sendContext.contextWindowTokens,
              persistedState.conversation?.contextSummary == compacted.summary,
              persistedState.conversation?.contextSummaryCursorMessageId == compacted.cursorMessageId,
              hasSameRequestMessages(persistedState.messages, as: sendContext) else {
            throw CancellationError()
        }
    }

    func rollbackPreflightCompaction(_ pending: PendingPreflightCompaction) {
        guard case .loaded(var currentState) = state,
              currentState.conversation?.contextSummary == pending.attemptedSummary,
              currentState.conversation?.contextSummaryCursorMessageId == pending.attemptedCursorMessageId else {
            clearPendingPreflightCompaction(pending)
            return
        }
        currentState.conversation?.contextSummary = pending.previousSummary
        currentState.conversation?.contextSummaryCursorMessageId = pending.previousCursorMessageId
        refreshContextUsage(in: &currentState)
        state = .loaded(currentState)
        clearPendingPreflightCompaction(pending)
    }

    func clearPendingPreflightCompaction(_ pending: PendingPreflightCompaction) {
        guard pendingPreflightCompaction?.assistantMessageId == pending.assistantMessageId,
              pendingPreflightCompaction?.attemptedCursorMessageId == pending.attemptedCursorMessageId else { return }
        pendingPreflightCompaction = nil
    }

    func hasSameRequestMessages(_ messages: [ChatMessage], as sendContext: SendMessageContext) -> Bool {
        // Compare original history, not the model-only attachment projection used for requests and compaction.
        messages.filter { $0.id != sendContext.assistantId }.elementsEqual(sendContext.messages) {
            $0.id == $1.id && $0.hasSameRequestContent(as: $1)
        }
    }
}
