//
//  ChatViewModel+MCP.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 25/07/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

extension ChatViewModel {
    func makeLoadedState(
        models: [LLMModel],
        mcpResult: MCPDiscoveryResult? = nil,
        pending: Conversation?,
        errorMessage: String? = nil
    ) -> LoadedState {
        let mcpTools = mcpResult?.tools ?? []
        let mcpServers = mcpResult?.servers ?? []
        let chatModels = models.filter {
            [.chat, .completion, .unknown, .imageGeneration].contains($0.mode)
        }
        let savedModelID = getChatPreferencesUseCase.getSelectedModelId()
        let selectedModel = chatModels.first(where: { $0.id == pending?.modelId })
            ?? chatModels.first(where: { $0.id == savedModelID })
            ?? chatModels.first
        let audioModelIDs = resolveAudioModelIdsUseCase.execute(from: models)
        var loadedState = LoadedState(
            conversation: pending,
            messages: pending?.messages ?? [],
            selectedModel: selectedModel,
            availableModels: chatModels,
            modelCatalogScope: settingsManager.getMCPAuthorizationScope(),
            conversationStarters: (pending?.messages ?? []).isEmpty
                ? getConversationStartersUseCase.execute(count: 4)
                : [],
            errorMessage: errorMessage,
            systemPrompt: pending?.systemPrompt ?? "",
            modelParameters: pending?.modelParameters ?? .default,
            contextWindowTokens: pending?.contextWindowTokens,
            showTokenUsage: getChatPreferencesUseCase.getShowTokenUsage(),
            ttsModelId: audioModelIDs.ttsModelId,
            transcriptionModelId: audioModelIDs.transcriptionModelId,
            isWebSearchEnabled: getChatPreferencesUseCase.getIsWebSearchEnabled(),
            isWebSearchToolConfigured: !getChatPreferencesUseCase.getWebSearchToolName().isEmpty,
            isMCPSupported: !mcpTools.isEmpty,
            availableMCPTools: mcpTools,
            availableMCPServers: mcpServers,
            failedMCPServerIds: mcpResult?.failedServerIds ?? [],
            enabledMCPToolIds: enabledMCPToolIds(
                savedIds: settingsManager.getEnabledMCPToolIds(),
                tools: mcpTools
            ),
            mcpToolPermissions: mcpToolPermissions(for: mcpTools)
        )
        refreshContextUsage(in: &loadedState)
        return loadedState
    }
    func handleMCPEvent(_ event: Event) {
        switch event {
        case .mcpButtonTapped:
            refreshMCPTools()
        case .mcpToolsRefreshed:
            refreshMCPTools()
        case .mcpToolToggled(let toolId, let enabled):
            toggleMCPTool(toolId: toolId, enabled: enabled)
        case .mcpToolsToggled(let toolIds, let enabled):
            toggleMCPTools(toolIds: toolIds, enabled: enabled)
        case .mcpToolPermissionChanged(let toolId, let permission):
            updateMCPToolPermission(toolId: toolId, permission: permission)
        case .mcpToolsPermissionChanged(let toolIds, let permission):
            updateMCPToolPermissions(toolIds: toolIds, permission: permission)
        case .mcpAuthorizationDecision(let batchId, let requestId, let decision):
            mcpAuthorizationCoordinator.select(decision, for: requestId, batchId: batchId)
        case .mcpAuthorizationSubmitted(let batchId):
            mcpAuthorizationCoordinator.submit(batchId: batchId)
        case .mcpAuthorizationDismissed(let batchId):
            mcpAuthorizationCoordinator.dismiss(batchId: batchId)
        default:
            break
        }
    }

    func refreshMCPTools(replacingCurrent: Bool = false) {
        guard case .loaded(let loadedState) = state else { return }
        guard !loadedState.isLoadingMCPTools || replacingCurrent else { return }
        mcpDiscoveryTask?.cancel()
        mcpDiscoveryGeneration += 1
        let generation = mcpDiscoveryGeneration
        let discoveryScope = settingsManager.getMCPAuthorizationScope()
        guard !discoveryScope.isEmpty else {
            var update = loadedState
            mcpDiscoveryTask = nil
            clearMCPTools(scope: discoveryScope, in: &update)
            update.isLoadingMCPTools = false
            update.mcpToolsError = String(localized: "MCP permissions require access to secure storage.")
            state = .loaded(update)
            return
        }
        observedMCPAuthorizationScope = discoveryScope
        let discoveryRevision = settingsManager.beginMCPToolDiscovery()
        var update = loadedState
        if update.mcpDiscoveryScope != discoveryScope {
            clearMCPTools(scope: discoveryScope, in: &update)
        }
        update.isLoadingMCPTools = true
        update.mcpToolsError = nil
        state = .loaded(update)
        let fetchUseCase = fetchMCPToolsUseCase

        mcpDiscoveryTask = Task { [weak self] in
            let result = await fetchUseCase.execute()
            self?.receiveMCPDiscovery(
                result,
                generation: generation,
                scope: discoveryScope,
                revision: discoveryRevision
            )
        }
    }

    func receiveMCPDiscovery(
        _ result: MCPDiscoveryResult,
        generation: Int,
        scope: String,
        revision: Int
    ) {
        defer {
            if mcpDiscoveryGeneration == generation { mcpDiscoveryTask = nil }
        }
        guard !Task.isCancelled, generation == mcpDiscoveryGeneration else { return }
        guard case .loaded(var currentState) = state else { return }
        guard scope == settingsManager.getMCPAuthorizationScope() else {
            currentState.isLoadingMCPTools = false
            state = .loaded(currentState)
            refreshMCPTools(replacingCurrent: true)
            return
        }
        let canRetainPreviousTools = currentState.mcpDiscoveryScope == scope
        if result.errorMessage != nil && result.servers.isEmpty {
            let didPublishFailure = settingsManager.publishMCPToolDiscoveryFailure(revision: revision)
            guard didPublishFailure else {
                currentState.isLoadingMCPTools = false
                state = .loaded(currentState)
                refreshMCPTools(replacingCurrent: true)
                return
            }
            applyMCPDiscoveryFailure(result, canRetainPreviousTools: canRetainPreviousTools, to: &currentState)
            currentState.mcpDiscoveryRevision = revision
            state = .loaded(currentState)
            return
        }
        let didPublishDiscovery = applyMCPDiscoverySuccess(
            result,
            canRetainPreviousTools: canRetainPreviousTools,
            scope: scope,
            revision: revision,
            to: &currentState
        )
        state = .loaded(currentState)
        if !didPublishDiscovery { refreshMCPTools(replacingCurrent: true) }
    }

    func applyMCPDiscoveryFailure(
        _ result: MCPDiscoveryResult,
        canRetainPreviousTools: Bool,
        to state: inout LoadedState
    ) {
        state.isLoadingMCPTools = false
        state.mcpToolsError = result.errorMessage
        if !canRetainPreviousTools {
            clearMCPTools(scope: settingsManager.getMCPAuthorizationScope(), in: &state)
        } else {
            state.failedMCPServerIds = Set(state.availableMCPServers.map(\.serverId))
        }
    }

    func applyMCPDiscoverySuccess(
        _ result: MCPDiscoveryResult,
        canRetainPreviousTools: Bool,
        scope: String,
        revision: Int,
        to state: inout LoadedState
    ) -> Bool {
        let discoveredTools = result.mergingPreviouslyDiscoveredTools(
            canRetainPreviousTools ? state.availableMCPTools : []
        )
        let normalizedEnabledIds = enabledMCPToolIds(
            savedIds: settingsManager.getEnabledMCPToolIds(),
            tools: discoveredTools
        )
        let didPublishDiscovery = settingsManager.publishMCPToolDiscovery(
            revision: revision,
            configurationKeys: mcpToolConfigurationKeys(for: result.tools),
            enabledToolIds: Array(normalizedEnabledIds),
            servers: result.servers,
            failedServerIds: result.failedServerIds
        )
        guard didPublishDiscovery else {
            state.isLoadingMCPTools = false
            return false
        }
        state.isMCPSupported = !discoveredTools.isEmpty
        state.availableMCPTools = discoveredTools
        state.availableMCPServers = result.servers
        state.failedMCPServerIds = result.failedServerIds
        state.mcpDiscoveryScope = scope
        state.mcpDiscoveryRevision = revision
        state.enabledMCPToolIds = normalizedEnabledIds
        state.mcpToolPermissions = mcpToolPermissions(for: discoveredTools)
        state.isLoadingMCPTools = false
        state.mcpToolsError = result.errorMessage
        refreshContextUsage(in: &state)
        return true
    }

    func toggleMCPTool(toolId: String, enabled: Bool) {
        toggleMCPTools(toolIds: [toolId], enabled: enabled)
    }

    func toggleMCPTools(toolIds: [String], enabled: Bool) {
        guard case .loaded(var loadedState) = state else { return }
        let configurableIds = configurableMCPTools(toolIds: toolIds, state: loadedState).map(\.id)
        guard !configurableIds.isEmpty else { return }
        if enabled {
            loadedState.enabledMCPToolIds.formUnion(configurableIds)
        } else {
            loadedState.enabledMCPToolIds.subtract(configurableIds)
        }
        settingsManager.setEnabledMCPToolIds(Array(loadedState.enabledMCPToolIds))
        refreshContextUsage(in: &loadedState)
        state = .loaded(loadedState)
    }

    func enabledMCPToolIds(savedIds: [String], tools: [MCPToolInfo]) -> Set<String> {
        MCPToolInfo.migratedEnabledToolIds(savedIds: savedIds, tools: tools)
    }

    func updateMCPToolPermission(toolId: String, permission: MCPToolPermission) {
        updateMCPToolPermissions(toolIds: [toolId], permission: permission)
    }

    func updateMCPToolPermissions(toolIds: [String], permission: MCPToolPermission) {
        guard case .loaded(var loadedState) = state else { return }
        let tools = configurableMCPTools(toolIds: toolIds, state: loadedState)
        guard !tools.isEmpty else { return }
        settingsManager.setMCPToolPermission(permission, for: tools.map(permissionKey))
        for tool in tools {
            loadedState.mcpToolPermissions[tool.id] = permission
        }
        state = .loaded(loadedState)
    }

    private func configurableMCPTools(toolIds: [String], state: LoadedState) -> [MCPToolInfo] {
        let requestedIds = Set(toolIds)
        return state.availableMCPTools.filter {
            requestedIds.contains($0.id)
                && $0.isInputSchemaSupported
                && !state.failedMCPServerIds.contains($0.serverId)
        }
    }

    func mcpToolPermissions(for tools: [MCPToolInfo]) -> [String: MCPToolPermission] {
        tools.reduce(into: [String: MCPToolPermission]()) { result, tool in
            result[tool.id] = settingsManager.getMCPToolPermission(for: permissionKey(for: tool))
        }
    }

    func refreshMCPToolSettings() {
        guard case .loaded(var loadedState) = state else { return }
        loadedState.enabledMCPToolIds = enabledMCPToolIds(
            savedIds: settingsManager.getEnabledMCPToolIds(),
            tools: loadedState.availableMCPTools
        )
        loadedState.mcpToolPermissions = mcpToolPermissions(for: loadedState.availableMCPTools)
        refreshContextUsage(in: &loadedState)
        state = .loaded(loadedState)
    }

    func permissionKey(for tool: MCPToolInfo) -> String {
        tool.permissionKey(
            serverBaseURL: settingsManager.getServerBaseURL(),
            authorizationScope: settingsManager.getMCPAuthorizationScope()
        )
    }

    func mcpToolConfigurationKeys(for tools: [MCPToolInfo]) -> [String: String] {
        tools.reduce(into: [String: String]()) { result, tool in
            result[tool.id] = permissionKey(for: tool)
        }
    }

    func observeMCPToolSettingsChanges() {
        mcpSettingsObservationTask?.cancel()
        mcpSettingsObservationTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(named: .mcpToolSettingsDidChange)
            for await _ in notifications {
                guard let self else { return }
                let currentScope = settingsManager.getMCPAuthorizationScope()
                let scopeChanged = currentScope != observedMCPAuthorizationScope
                observedMCPAuthorizationScope = currentScope
                if scopeChanged { cancelActiveStreaming() }
                let needsRefresh = scopeChanged || mcpConfigurationNeedsRefresh()
                if needsRefresh {
                    refreshMCPTools(replacingCurrent: true)
                } else {
                    refreshMCPToolSettings()
                }
            }
        }
    }

    func mcpConfigurationNeedsRefresh() -> Bool {
        guard case .loaded(let loadedState) = state, !loadedState.isLoadingMCPTools else { return false }
        if loadedState.mcpDiscoveryRevision < settingsManager.getPublishedMCPToolDiscoveryRevision() {
            return true
        }
        return loadedState.availableMCPTools.contains { tool in
            settingsManager.getMCPToolConfigurationKey(for: tool.id) != permissionKey(for: tool)
        }
    }

    func clearMCPTools(scope: String, in state: inout LoadedState) {
        state.isMCPSupported = false
        state.availableMCPTools = []
        state.availableMCPServers = []
        state.failedMCPServerIds = []
        state.enabledMCPToolIds = []
        state.mcpToolPermissions = [:]
        state.mcpDiscoveryScope = scope
        state.mcpDiscoveryRevision = 0
        refreshContextUsage(in: &state)
    }
}
