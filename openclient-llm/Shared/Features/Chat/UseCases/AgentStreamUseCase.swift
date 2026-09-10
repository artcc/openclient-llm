//
//  AgentStreamUseCase.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 05/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

// MARK: - AgentEvent

enum AgentEvent: Sendable {
    case token(String)
    case reasoning(String)
    case toolCallStarted(ToolCall)
    case toolCallCompleted(toolCallId: String, result: String, searchResults: [LiteLLMSearchResult]?)
    case transcriptAppended([ChatMessage])
    case usage(TokenUsage)
    case promptUsage(Int?)
    case image(Data)
    case generatedImage(GeneratedImage)
    case completed
}

nonisolated struct AgentToolContext: Sendable {
    let toolRegistry: ToolRegistry
    let additionalExecutionTime: Duration
    let isConfigurationCurrent: @MainActor @Sendable () -> Bool

    init(
        toolRegistry: ToolRegistry,
        additionalExecutionTime: Duration = .zero,
        isConfigurationCurrent: @escaping @MainActor @Sendable () -> Bool = { true }
    ) {
        self.toolRegistry = toolRegistry
        self.additionalExecutionTime = additionalExecutionTime
        self.isConfigurationCurrent = isConfigurationCurrent
    }
}

// MARK: - AgentStreamUseCaseProtocol

protocol AgentStreamUseCaseProtocol: Sendable {
    func execute(
        messages: [ChatMessage],
        model: String,
        parameters: ModelParameters,
        contextWindowTokens: Int?,
        toolContext: AgentToolContext
    ) -> AsyncThrowingStream<AgentEvent, Error>
}

extension AgentStreamUseCaseProtocol {
    func execute(
        messages: [ChatMessage],
        model: String,
        parameters: ModelParameters,
        contextWindowTokens: Int? = nil,
        toolRegistry: ToolRegistry
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        execute(
            messages: messages,
            model: model,
            parameters: parameters,
            contextWindowTokens: contextWindowTokens,
            toolContext: AgentToolContext(toolRegistry: toolRegistry)
        )
    }
}

// MARK: - AgentStreamUseCase

struct AgentStreamUseCase: AgentStreamUseCaseProtocol {
    // MARK: - Properties

    private static let maxIterations = 15
    private static let maxToolCalls = 20
    private static let maxToolCallsPerIteration = 8
    private static let maximumToolResultCharacters = 12_000
    private let repository: ChatRepositoryProtocol
    private let timeout: Duration
    private let chunkDelay: Duration

    // MARK: - Init

    init(
        repository: ChatRepositoryProtocol = ChatRepository(),
        timeout: Duration = .seconds(300),
        chunkDelay: Duration = .milliseconds(20)
    ) {
        self.repository = repository
        self.timeout = timeout
        self.chunkDelay = chunkDelay
    }

    // MARK: - Execute

    func execute(
        messages: [ChatMessage],
        model: String,
        parameters: ModelParameters,
        contextWindowTokens: Int? = nil,
        toolContext: AgentToolContext
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let timeoutController = AgentTimeoutController(timeout: timeout + toolContext.additionalExecutionTime)
            let executionController = AgentExecutionController()
            let context = AgentLoopContext(
                model: model,
                parameters: parameters,
                contextWindowTokens: contextWindowTokens,
                toolRegistry: toolContext.toolRegistry,
                isConfigurationCurrent: toolContext.isConfigurationCurrent,
                timeoutController: timeoutController,
                continuation: continuation
            )
            let task = Task {
                await timeoutController.start {
                    continuation.finish(throwing: AgentStreamError.timedOut)
                    Task { await executionController.cancel() }
                }
                defer { Task { await timeoutController.cancel() } }
                do {
                    try await runAgentLoop(messages: messages, context: context)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            Task { await executionController.register(task) }
            continuation.onTermination = { _ in
                task.cancel()
                Task {
                    await executionController.cancel()
                    await timeoutController.cancel()
                }
            }
        }
    }
}

// MARK: - AgentLoopContext

private nonisolated struct AgentLoopContext: Sendable {
    let model: String
    let parameters: ModelParameters
    let contextWindowTokens: Int?
    let toolRegistry: ToolRegistry
    let isConfigurationCurrent: @MainActor @Sendable () -> Bool
    let timeoutController: AgentTimeoutController
    let continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
}

private nonisolated struct AgentRoundContext: Sendable {
    let requestMessages: [ChatMessage]
    let loop: AgentLoopContext
}

// MARK: - Private

private extension AgentStreamUseCase {
    func runAgentLoop(messages: [ChatMessage], context: AgentLoopContext) async throws {
        var conversationMessages = messages
        var toolCallCount = 0
        var aggregateUsage = TokenUsage()
        var forceFinalResponse = false

        for iteration in 1...Self.maxIterations {
            try Task.checkCancellation()
            if iteration == Self.maxIterations { forceFinalResponse = true }
            LogManager.debug("agentLoop iteration=\(iteration) messages=\(conversationMessages.count)")
            let tools = forceFinalResponse ? [] : context.toolRegistry.definitions
            let requestMessages = try rebudgetedMessages(
                conversationMessages,
                contextWindowTokens: context.contextWindowTokens,
                tools: tools
            )
            let response = try await request(context: context, messages: requestMessages, tools: tools)
            aggregateUsage = emitUsage(response.usage, aggregate: aggregateUsage, continuation: context.continuation)
            guard let choice = response.choices.first else { throw AgentStreamError.invalidResponse }
            let toolCalls = choice.message.toolCalls ?? []
            if toolCalls.isEmpty, hasPresentableFinalContent(choice) {
                await context.timeoutController.pause()
            }

            if !toolCalls.isEmpty {
                guard !forceFinalResponse else { throw AgentStreamError.iterationLimitReached }
                forceFinalResponse = try await completeToolRound(
                    choice: choice,
                    toolCalls: toolCalls,
                    conversationMessages: &conversationMessages,
                    toolCallCount: &toolCallCount,
                    context: AgentRoundContext(requestMessages: requestMessages, loop: context)
                )
            } else if try await handleFinalChoice(
                choice,
                continuation: context.continuation,
                delay: chunkDelay
            ) {
                guard !forceFinalResponse else { throw AgentStreamError.invalidResponse }
                forceFinalResponse = true
            } else {
                context.continuation.yield(.completed)
                return
            }
        }
        throw AgentStreamError.iterationLimitReached
    }

    func request(
        context: AgentLoopContext,
        messages: [ChatMessage],
        tools: [ToolDefinition]
    ) async throws -> ChatCompletionResponse {
        guard context.isConfigurationCurrent() else { throw AgentStreamError.configurationChanged }
        let response = try await repository.agentCompletion(
            messages: messages,
            model: context.model,
            parameters: context.parameters,
            tools: tools.isEmpty ? nil : tools
        )
        guard context.isConfigurationCurrent() else { throw AgentStreamError.configurationChanged }
        return response
    }

    func completeToolRound(
        choice: ChatCompletionResponse.Choice,
        toolCalls: [ToolCall],
        conversationMessages: inout [ChatMessage],
        toolCallCount: inout Int,
        context: AgentRoundContext
    ) async throws -> Bool {
        guard Set(toolCalls.map(\.id)).count == toolCalls.count else {
            throw AgentStreamError.invalidResponse
        }
        guard try yieldNativeImages(choice, continuation: context.loop.continuation) else {
            throw CancellationError()
        }
        let remaining = max(0, Self.maxToolCalls - toolCallCount)
        let executableCount = min(toolCalls.count, min(Self.maxToolCallsPerIteration, remaining))
        let executable = Array(toolCalls.prefix(executableCount))
        let rejected = Array(toolCalls.dropFirst(executableCount))
        toolCallCount += executable.count
        let assistant = ChatMessage(
            role: .assistant,
            content: choice.message.content ?? "",
            toolCalls: toolCalls
        )
        let willForceFinal = toolCallCount >= Self.maxToolCalls || !rejected.isEmpty
        let nextTools = willForceFinal ? [] : context.loop.toolRegistry.definitions
        let toolPlaceholders = toolCalls.map {
            ChatMessage(role: .tool, content: "", toolCallId: $0.id, toolName: $0.function.name)
        }
        let resultLimit = try toolResultCharacterLimit(
            requestMessages: context.requestMessages + [assistant] + toolPlaceholders,
            contextWindowTokens: context.loop.contextWindowTokens,
            tools: nextTools,
            resultCount: toolCalls.count
        )
        let executedResults = try await authorizedToolResults(
            executable,
            context: context.loop,
            maximumCharacters: resultLimit
        )
        let results = orderedResults(
            toolCalls: toolCalls,
            executed: executedResults,
            rejected: rejected,
            maximumBytes: resultLimit
        )
        let transcript = [assistant] + results.map(toolMessage)
        conversationMessages.append(contentsOf: transcript)
        context.loop.continuation.yield(.transcriptAppended(transcript))
        return willForceFinal
    }

    func authorizedToolResults(
        _ toolCalls: [ToolCall],
        context: AgentLoopContext,
        maximumCharacters: Int
    ) async throws -> [ToolCallResult] {
        let plan = context.toolRegistry.makeAuthorizationPlan(for: toolCalls)
        let outcomes = try await resolveAuthorization(plan, context: context)
        try Task.checkCancellation()
        guard context.isConfigurationCurrent() else { throw AgentStreamError.configurationChanged }
        let authorized = outcomes.compactMap { outcome -> ToolRegistry.AuthorizedInvocation? in
            guard case .authorized(let invocation) = outcome else { return nil }
            return invocation
        }
        let denied = outcomes.compactMap { outcome -> ToolCallResult? in
            guard case .denied(let toolCall, let reason) = outcome else { return nil }
            return ToolCallResult(
                toolCallId: toolCall.id,
                toolName: toolCall.function.name,
                executionResult: ToolExecutionResult(text: reason)
            )
        }
        let executed = try await executeToolCalls(
            authorized,
            registry: context.toolRegistry,
            isConfigurationCurrent: context.isConfigurationCurrent,
            continuation: context.continuation,
            maximumCharacters: maximumCharacters
        )
        return executed + denied.map {
            boundedToolResult($0, maximumCharacters: maximumCharacters)
        }
    }

    func executeToolCalls(
        _ invocations: [ToolRegistry.AuthorizedInvocation],
        registry: ToolRegistry,
        isConfigurationCurrent: @escaping @MainActor @Sendable () -> Bool,
        continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation,
        maximumCharacters: Int
    ) async throws -> [ToolCallResult] {
        try await withThrowingTaskGroup(of: ToolCallResult.self) { group in
            for invocation in invocations {
                continuation.yield(.toolCallStarted(invocation.toolCall))
                group.addTask {
                    try await executeToolCall(
                        invocation,
                        registry: registry,
                        isConfigurationCurrent: isConfigurationCurrent,
                        continuation: continuation
                    )
                }
            }
            var results: [ToolCallResult] = []
            for try await result in group {
                try Task.checkCancellation()
                let bounded = boundedToolResult(result, maximumCharacters: maximumCharacters)
                results.append(bounded)
                continuation.yield(.toolCallCompleted(
                    toolCallId: bounded.toolCallId,
                    result: bounded.executionResult.text,
                    searchResults: bounded.executionResult.searchResults
                ))
            }
            return results
        }
    }

    func executeToolCall(
        _ invocation: ToolRegistry.AuthorizedInvocation,
        registry: ToolRegistry,
        isConfigurationCurrent: @escaping @MainActor @Sendable () -> Bool,
        continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    ) async throws -> ToolCallResult {
        let toolCall = invocation.toolCall
        do {
            guard isConfigurationCurrent() else { throw AgentStreamError.configurationChanged }
            let result = try await registry.execute(invocation)
            try Task.checkCancellation()
            guard isConfigurationCurrent() else { throw AgentStreamError.configurationChanged }
            // Publish before the task group collects results so a sibling failure cannot discard completed images.
            for image in result.images {
                continuation.yield(.generatedImage(image))
            }
            return ToolCallResult(
                toolCallId: toolCall.id,
                toolName: toolCall.function.name,
                executionResult: result
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AgentStreamError where error == .configurationChanged {
            throw error
        } catch {
            return ToolCallResult(
                toolCallId: toolCall.id,
                toolName: toolCall.function.name,
                executionResult: ToolExecutionResult(
                    text: "Error executing \(toolCall.function.name): \(error.localizedDescription)"
                )
            )
        }
    }

    func resolveAuthorization(
        _ plan: ToolRegistry.AuthorizationPlan,
        context: AgentLoopContext
    ) async throws -> [ToolRegistry.AuthorizationOutcome] {
        guard plan.requiresUserDecision else {
            return try await context.toolRegistry.resolveAuthorization(plan)
        }
        await context.timeoutController.pause()
        do {
            let outcomes = try await context.toolRegistry.resolveAuthorization(plan)
            await context.timeoutController.resume()
            return outcomes
        } catch {
            await context.timeoutController.cancel()
            throw error
        }
    }

    func orderedResults(
        toolCalls: [ToolCall],
        executed: [ToolCallResult],
        rejected: [ToolCall],
        maximumBytes: Int
    ) -> [ToolCallResult] {
        let executedById = executed.reduce(into: [String: ToolCallResult]()) { results, result in
            results[result.toolCallId] = result
        }
        let rejectedIds = Set(rejected.map(\.id))
        return toolCalls.compactMap { toolCall in
            if let result = executedById[toolCall.id] { return result }
            guard rejectedIds.contains(toolCall.id) else { return nil }
            let result = ToolCallResult(
                toolCallId: toolCall.id,
                toolName: toolCall.function.name,
                executionResult: ToolExecutionResult(text: "Tool execution skipped: agent tool-call budget exceeded.")
            )
            return boundedToolResult(result, maximumCharacters: maximumBytes)
        }
    }

    func toolMessage(_ result: ToolCallResult) -> ChatMessage {
        return ChatMessage(
            role: .tool,
            content: result.executionResult.text,
            toolCallId: result.toolCallId,
            toolName: result.toolName
        )
    }

    func emitUsage(
        _ usage: ChatCompletionResponse.Usage?,
        aggregate: TokenUsage,
        continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    ) -> TokenUsage {
        guard let usage else {
            continuation.yield(.promptUsage(nil))
            return aggregate
        }
        let updated = TokenUsage(
            promptTokens: aggregate.promptTokens + (usage.promptTokens ?? 0),
            completionTokens: aggregate.completionTokens + (usage.completionTokens ?? 0),
            totalTokens: aggregate.totalTokens + (usage.totalTokens ?? 0)
        )
        continuation.yield(.usage(updated))
        continuation.yield(.promptUsage(usage.promptTokens.flatMap { $0 > 0 ? $0 : nil }))
        return updated
    }

    func rebudgetedMessages(
        _ messages: [ChatMessage],
        contextWindowTokens: Int?,
        tools: [ToolDefinition]
    ) throws -> [ChatMessage] {
        guard let contextWindowTokens, contextWindowTokens > 0 else { return messages }
        let systemPrompt = messages.first(where: { $0.role == .system })?.content ?? ""
        let conversation = messages.filter { $0.role != .system }
        let context = ContextWindowBuilder().build(
            messages: conversation,
            systemPrompt: systemPrompt,
            summary: nil,
            model: LLMModel(id: "agent", maxInputTokens: contextWindowTokens),
            tools: tools
        )
        guard !context.isLatestTurnOverBudget else { throw ChatContextError.latestTurnExceedsContextWindow }
        if systemPrompt.isEmpty { return context.messages }
        return [ChatMessage(role: .system, content: systemPrompt)] + context.messages
    }

    func toolResultCharacterLimit(
        requestMessages: [ChatMessage],
        contextWindowTokens: Int?,
        tools: [ToolDefinition],
        resultCount: Int
    ) throws -> Int {
        guard let contextWindowTokens, contextWindowTokens > 0 else { return Self.maximumToolResultCharacters }
        let systemPrompt = requestMessages.first(where: { $0.role == .system })?.content ?? ""
        let messages = requestMessages.filter { $0.role != .system }
        let builder = ContextWindowBuilder()
        let model = LLMModel(id: "agent", maxInputTokens: contextWindowTokens)
        let estimated = builder.estimatedInputTokens(messages: messages, systemPrompt: systemPrompt, tools: tools)
        guard estimated <= builder.usableInputTokens(for: contextWindowTokens) else {
            throw ChatContextError.latestTurnExceedsContextWindow
        }
        let remaining = builder.remainingInputTokens(
            messages: messages,
            systemPrompt: systemPrompt,
            model: model,
            tools: tools
        ) ?? 0
        let tokensPerResult = max(0, remaining) / max(1, resultCount)
        let cappedTokens = min(tokensPerResult, Self.maximumToolResultCharacters / 3)
        return cappedTokens * 3
    }
}
