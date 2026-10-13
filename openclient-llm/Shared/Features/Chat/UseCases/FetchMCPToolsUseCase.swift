//
//  FetchMCPToolsUseCase.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 25/07/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

nonisolated struct MCPDiscoveryResult: Sendable {
    let servers: [MCPServerInfo]
    let tools: [MCPToolInfo]
    let errorMessage: String?
    let failedServerIds: Set<String>

    init(
        servers: [MCPServerInfo],
        tools: [MCPToolInfo],
        errorMessage: String? = nil,
        failedServerIds: Set<String> = []
    ) {
        self.servers = servers
        self.tools = tools
        self.errorMessage = errorMessage
        self.failedServerIds = failedServerIds
    }

    func mergingPreviouslyDiscoveredTools(_ previousTools: [MCPToolInfo]) -> [MCPToolInfo] {
        let serversById = servers.reduce(into: [String: MCPServerInfo]()) { result, server in
            result[server.serverId] = server
        }
        let discoveredIds = Set(tools.map(\.id))
        let retainedTools = previousTools.filter { tool in
            guard !discoveredIds.contains(tool.id),
                  failedServerIds.contains(tool.serverId),
                  let server = serversById[tool.serverId] else { return false }
            guard let allowedTools = server.allowedTools else { return true }
            return allowedTools.contains(tool.name)
        }
        var seenIds: Set<String> = []
        return (tools + retainedTools).filter { seenIds.insert($0.id).inserted }
    }
}

protocol FetchMCPToolsUseCaseProtocol: Sendable {
    func execute() async -> MCPDiscoveryResult
}

struct FetchMCPToolsUseCase: FetchMCPToolsUseCaseProtocol {
    // MARK: - Properties

    private let repository: MCPRepositoryProtocol?
    private let settingsManager: SettingsManagerProtocol

    private nonisolated struct ServerTools: Sendable {
        let index: Int
        let server: MCPServerInfo
        let tools: [MCPToolInfo]?
    }

    // MARK: - Init

    init(
        repository: MCPRepositoryProtocol? = nil,
        settingsManager: SettingsManagerProtocol = SettingsManager()
    ) {
        self.repository = repository
        self.settingsManager = settingsManager
    }

    // MARK: - Execute

    func execute() async -> MCPDiscoveryResult {
        let empty = MCPDiscoveryResult(servers: [], tools: [])
        let serverBaseURL = settingsManager.getServerBaseURL()
        let apiKey = settingsManager.getAPIKey()
        let authorizationScope = settingsManager.getMCPAuthorizationScope()
        guard !serverBaseURL.isEmpty, !authorizationScope.isEmpty else { return empty }
        let repository = repository ?? MCPRepository(apiClient: APIClient(
            serverBaseURL: serverBaseURL,
            apiKey: apiKey
        ))
        do {
            let servers = try await repository.fetchServers()
            guard !Task.isCancelled,
                  isConfigurationCurrent(
                    serverBaseURL: serverBaseURL,
                    apiKey: apiKey,
                    authorizationScope: authorizationScope
                  ) else { return empty }
            guard !servers.isEmpty else { return empty }

            let serverResults = await discoverTools(for: servers, repository: repository)
            guard !Task.isCancelled,
                  isConfigurationCurrent(
                    serverBaseURL: serverBaseURL,
                    apiKey: apiKey,
                    authorizationScope: authorizationScope
                  ) else { return empty }
            return discoveryResult(servers: servers, serverResults: serverResults)
        } catch {
            guard !Task.isCancelled else { return empty }
            LogManager.debug("FetchMCPToolsUseCase: MCP not available — \(error.localizedDescription)")
            let errorMessage = String(localized: """
                MCP tools could not be loaded. Check the server connection and try again.
                """)
            return MCPDiscoveryResult(
                servers: [],
                tools: [],
                errorMessage: errorMessage
            )
        }
    }
}

private extension FetchMCPToolsUseCase {
    private func discoverTools(
        for servers: [MCPServerInfo],
        repository: MCPRepositoryProtocol
    ) async -> [ServerTools] {
        await withTaskGroup(of: ServerTools.self) { group in
            for (index, server) in servers.enumerated() {
                group.addTask {
                    let tools = try? await repository.fetchTools(serverId: server.serverId)
                    return ServerTools(index: index, server: server, tools: tools)
                }
            }
            var results: [ServerTools] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.index < $1.index }
        }
    }

    private func discoveryResult(
        servers: [MCPServerInfo],
        serverResults: [ServerTools]
    ) -> MCPDiscoveryResult {
        var tools: [MCPToolInfo] = []
        var failedServerNames: [String] = []
        var failedServerIds: Set<String> = []
        for result in serverResults {
            guard let discoveredTools = result.tools else {
                failedServerNames.append(result.server.displayName)
                failedServerIds.insert(result.server.serverId)
                continue
            }
            let server = result.server
            tools += discoveredTools
                .map { $0.withServer(server) }
                .filter { tool in
                    // LiteLLM can redact this list; successful tool discovery already enforces server permissions.
                    guard let allowedTools = server.allowedTools, !allowedTools.isEmpty else { return true }
                    return allowedTools.contains(tool.name)
                }
        }
        let errorMessage = failedServerNames.isEmpty ? nil : String(
            localized: "Some MCP servers could not be loaded: \(failedServerNames.joined(separator: ", "))."
        )
        return MCPDiscoveryResult(
            servers: servers,
            tools: tools,
            errorMessage: errorMessage,
            failedServerIds: failedServerIds
        )
    }

    func isConfigurationCurrent(
        serverBaseURL: String,
        apiKey: String,
        authorizationScope: String
    ) -> Bool {
        MCPToolInfo.normalizedServerURL(settingsManager.getServerBaseURL())
            == MCPToolInfo.normalizedServerURL(serverBaseURL)
            && settingsManager.getAPIKey() == apiKey
            && settingsManager.getMCPAuthorizationScope() == authorizationScope
    }
}
