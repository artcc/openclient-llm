//
//  ToolRegistry.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 05/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

actor ToolExecutionPermit {
    private var wasConsumed = false

    func consume() -> Bool {
        guard !wasConsumed else { return false }
        wasConsumed = true
        return true
    }
}

enum ToolRegistryError: LocalizedError, Sendable {
    case permitAlreadyUsed

    var errorDescription: String? {
        String(localized: "The tool execution permit was already used.")
    }
}

struct ToolRegistry: Sendable {
    // MARK: - Authorization

    struct AuthorizationPlan: Sendable {
        fileprivate let entries: [PlannedToolCall]

        var requiresUserDecision: Bool {
            entries.contains { entry in
                if case .ask = entry { return true }
                return false
            }
        }
    }

    struct AuthorizedInvocation: Sendable {
        let toolCall: ToolCall
        fileprivate let tool: (any ChatToolProtocol)?
        fileprivate let mcpApprovedByUser: Bool?
        fileprivate let permit = ToolExecutionPermit()

        fileprivate init(
            toolCall: ToolCall,
            tool: (any ChatToolProtocol)?,
            mcpApprovedByUser: Bool?
        ) {
            self.toolCall = toolCall
            self.tool = tool
            self.mcpApprovedByUser = mcpApprovedByUser
        }
    }

    enum AuthorizationOutcome: Sendable {
        case authorized(AuthorizedInvocation)
        case denied(toolCall: ToolCall, reason: String)
    }

    // MARK: - Properties

    private let tools: [String: any ChatToolProtocol]
    private let mcpAuthorizer: (any MCPToolAuthorizing)?

    var definitions: [ToolDefinition] {
        tools.values.compactMap { tool in
            guard tool.isAvailableForAdvertisement else { return nil }
            if let mcpTool = tool as? any MCPAuthorizableToolProtocol,
               !mcpTool.isAvailableForAdvertisement {
                return nil
            }
            return tool.definition
        }
    }

    // MARK: - Init

    init(
        tools: [any ChatToolProtocol],
        mcpAuthorizer: (any MCPToolAuthorizing)? = nil
    ) {
        self.tools = tools.reduce(into: [String: any ChatToolProtocol]()) { result, tool in
            let name = tool.definition.function.name
            if result[name] == nil { result[name] = tool }
        }
        self.mcpAuthorizer = mcpAuthorizer
    }

    // MARK: - Authorization

    func makeAuthorizationPlan(for toolCalls: [ToolCall]) -> AuthorizationPlan {
        AuthorizationPlan(entries: toolCalls.map(plannedToolCall))
    }

    func resolveAuthorization(_ plan: AuthorizationPlan) async throws -> [AuthorizationOutcome] {
        let requests = plan.entries.compactMap { entry -> MCPToolAuthorizationRequest? in
            guard case .ask(_, _, let request) = entry else { return nil }
            return request
        }
        let decisions: [UUID: MCPToolAuthorizationDecision]
        if requests.isEmpty {
            decisions = [:]
        } else if let mcpAuthorizer {
            decisions = try await mcpAuthorizer.authorize(requests)
        } else {
            decisions = Dictionary(uniqueKeysWithValues: requests.map { ($0.id, .denyOnce) })
        }

        return plan.entries.map { entry in
            switch entry {
            case .automatic(let toolCall, let tool, let mcpApprovedByUser):
                return .authorized(AuthorizedInvocation(
                    toolCall: toolCall,
                    tool: tool,
                    mcpApprovedByUser: mcpApprovedByUser
                ))
            case .ask(let toolCall, let tool, let request):
                guard decisions[request.id]?.allowsExecution == true else {
                    return .denied(toolCall: toolCall, reason: Self.userDenialMessage)
                }
                return .authorized(AuthorizedInvocation(
                    toolCall: toolCall,
                    tool: tool,
                    mcpApprovedByUser: true
                ))
            case .denied(let toolCall, let reason):
                return .denied(toolCall: toolCall, reason: reason)
            }
        }
    }

    // MARK: - Execute

    func execute(_ invocation: AuthorizedInvocation) async throws -> ToolExecutionResult {
        try Task.checkCancellation()
        guard await invocation.permit.consume() else { throw ToolRegistryError.permitAlreadyUsed }
        guard let tool = invocation.tool else {
            return ToolExecutionResult(text: "Unknown tool: \(invocation.toolCall.function.name)")
        }
        if let mcpTool = tool as? any MCPAuthorizableToolProtocol,
           let approvedByUser = invocation.mcpApprovedByUser {
            return try await mcpTool.executeAuthorized(
                arguments: invocation.toolCall.function.arguments,
                approvedByUser: approvedByUser
            )
        }
        try Task.checkCancellation()
        return try await tool.execute(arguments: invocation.toolCall.function.arguments)
    }

    // MARK: - Factory

    static func `default`(
        webSearchEnabled: Bool = true,
        includesMemoryTools: Bool = true,
        webSearchUseCase: WebSearchUseCaseProtocol = WebSearchUseCase(),
        memoryManager: MemoryManagerProtocol? = nil
    ) -> ToolRegistry {
        var tools: [any ChatToolProtocol] = [GetCurrentDatetimeTool()]
        if includesMemoryTools {
            let resolvedMemoryManager = memoryManager ?? MemoryManager()
            tools.append(SaveMemoryTool(memoryManager: resolvedMemoryManager))
            tools.append(DeleteMemoryTool(memoryManager: resolvedMemoryManager))
        }
        if webSearchEnabled {
            tools.append(WebSearchTool(webSearchUseCase: webSearchUseCase))
        }
        return ToolRegistry(tools: tools)
    }
}

fileprivate extension ToolRegistry {
    enum PlannedToolCall: Sendable {
        case automatic(ToolCall, (any ChatToolProtocol)?, mcpApprovedByUser: Bool?)
        case ask(ToolCall, any ChatToolProtocol, MCPToolAuthorizationRequest)
        case denied(ToolCall, String)
    }

    static let userDenialMessage = "Tool execution was denied by the user. Do not retry this tool."
    static let policyDenialMessage = "Tool execution was denied by the user's policy. Do not retry this tool."

    func plannedToolCall(_ toolCall: ToolCall) -> PlannedToolCall {
        guard let tool = tools[toolCall.function.name] else {
            return .automatic(toolCall, nil, mcpApprovedByUser: nil)
        }
        guard let mcpTool = tool as? any MCPAuthorizableToolProtocol else {
            return .automatic(toolCall, tool, mcpApprovedByUser: nil)
        }
        do {
            try mcpTool.validateForAuthorization(arguments: toolCall.function.arguments)
        } catch {
            return .denied(toolCall, "Error executing \(toolCall.function.name): \(error.localizedDescription)")
        }

        let metadata = mcpTool.authorizationMetadata
        switch metadata.permission {
        case .alwaysAllow:
            return .automatic(toolCall, tool, mcpApprovedByUser: false)
        case .ask:
            let request = MCPToolAuthorizationRequest(
                id: UUID(),
                toolCallId: toolCall.id,
                toolName: toolCall.function.name,
                arguments: toolCall.function.arguments,
                metadata: metadata
            )
            return .ask(toolCall, tool, request)
        case .deny:
            return .denied(toolCall, Self.policyDenialMessage)
        }
    }
}
