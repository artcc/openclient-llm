//
//  SettingsViewModel+Server.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 02/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

extension SettingsViewModel {
    func updateServerURL(_ url: String) {
        guard case .loaded(var loadedState) = state else { return }
        loadedState.serverURL = url
        markServerConfigurationEdited(&loadedState)
        state = .loaded(loadedState)
    }

    func updateAPIKey(_ key: String) {
        guard case .loaded(var loadedState) = state else { return }
        loadedState.apiKey = key
        markServerConfigurationEdited(&loadedState)
        state = .loaded(loadedState)
    }

    func handleAdvancedServerEvent(_ event: Event) {
        guard case .loaded(var loadedState) = state else { return }
        switch event {
        case .advancedServerSettingsOpened:
            loadedState.customHeaderDraft = loadedState.customHeaders
            loadedState.chatIDHeaderNameDraft = loadedState.chatIDHeaderName
        case .advancedServerSettingsCancelled:
            loadedState.customHeaderDraft = nil
            loadedState.chatIDHeaderNameDraft = nil
        case .advancedServerSettingsApplied:
            applyCustomHeaderDraft(&loadedState)
        case .customHeaderAdded, .customHeaderRemoved, .customHeaderChanged:
            updateCustomHeaderDraft(event, in: &loadedState)
        case .chatIDHeaderToggled, .chatIDHeaderNameChanged:
            updateChatIDHeaderDraft(event, in: &loadedState)
        default:
            return
        }
        state = .loaded(loadedState)
    }

    func testConnection() {
        guard case .loaded(var loadedState) = state else { return }
        if let error = ServerHTTPHeader.validationError(
            in: loadedState.customHeaders, chatIDHeaderName: loadedState.chatIDHeaderName
        ) {
            loadedState.connectionStatus = .failure(error)
            state = .loaded(loadedState)
            return
        }
        cancelServerChecks()
        let revision = serverConfigurationRevision
        let serverURL = loadedState.serverURL
        let apiKey = loadedState.apiKey
        let headers = loadedState.customHeaders
        loadedState.connectionStatus = .testing
        state = .loaded(loadedState)
        serverConnectionTask = Task {
            let status: ConnectionStatus
            do {
                try await testServerConnectionUseCase.execute(
                    serverURL: serverURL, apiKey: apiKey, customHeaders: headers
                )
                status = .success
            } catch {
                status = .failure(error.localizedDescription)
            }
            guard !Task.isCancelled, revision == serverConfigurationRevision,
                  case .loaded(var currentState) = state else { return }
            currentState.connectionStatus = status
            state = .loaded(currentState)
            refreshLiteLLMHint(serverURL: serverURL, customHeaders: headers)
        }
    }

    func saveSettings() {
        guard case .loaded(var loadedState) = state else { return }
        if let error = ServerHTTPHeader.validationError(
            in: loadedState.customHeaders, chatIDHeaderName: loadedState.chatIDHeaderName
        ) {
            loadedState.isSaved = false
            loadedState.serverPersistenceError = error
            state = .loaded(loadedState)
            return
        }
        let configurationChanged = loadedState.serverURL != settingsManager.getServerBaseURL()
            || loadedState.apiKey != settingsManager.getAPIKey()
            || !ServerHTTPHeader.hasSameValues(loadedState.customHeaders, settingsManager.getCustomHeaders())
            || loadedState.chatIDHeaderName?.lowercased() != settingsManager.getChatIDHeaderName()?.lowercased()
        guard saveServerConfigurationUseCase.execute(
            serverURL: loadedState.serverURL, apiKey: loadedState.apiKey,
            customHeaders: loadedState.customHeaders, chatIDHeaderName: loadedState.chatIDHeaderName
        ) else {
            loadedState.isSaved = false
            loadedState.serverPersistenceFailureCount += 1
            loadedState.serverPersistenceError = String(localized: "The server configuration could not be saved.")
            state = .loaded(loadedState)
            return
        }
        loadedState.isSaved = true
        loadedState.serverPersistenceError = nil
        state = .loaded(loadedState)
        refreshLiteLLMHint(serverURL: loadedState.serverURL, customHeaders: loadedState.customHeaders)
        if configurationChanged { fetchMCPTools(replacingCurrent: true) }
    }

    func cancelServerChecks() {
        serverConfigurationRevision += 1
        serverConnectionTask?.cancel()
        serverHealthTask?.cancel()
    }

    func refreshLiteLLMHint(serverURL: String, customHeaders: [ServerHTTPHeader]) {
        serverHealthTask?.cancel()
        let revision = serverConfigurationRevision
        serverHealthTask = Task {
            let isLiteLLM = await checkLiteLLMHealthUseCase.execute(serverURL: serverURL, customHeaders: customHeaders)
            guard !Task.isCancelled, revision == serverConfigurationRevision,
                  case .loaded(var currentState) = state else { return }
            currentState.showLiteLLMHint = !isLiteLLM
            state = .loaded(currentState)
        }
    }

    private func markServerConfigurationEdited(_ loadedState: inout LoadedState) {
        cancelServerChecks()
        loadedState.connectionStatus = .idle
        loadedState.isSaved = false
        loadedState.serverPersistenceError = nil
    }

    private func updateCustomHeaderDraft(_ event: Event, in loadedState: inout LoadedState) {
        switch event {
        case .customHeaderAdded:
            guard let draft = loadedState.customHeaderDraft,
                  draft.count + (loadedState.chatIDHeaderNameDraft == nil ? 0 : 1) < ServerHTTPHeader.maximumCount
            else { return }
            loadedState.customHeaderDraft?.append(ServerHTTPHeader())
        case .customHeaderRemoved(let id):
            loadedState.customHeaderDraft?.removeAll { $0.id == id }
        case .customHeaderChanged(let header):
            guard let index = loadedState.customHeaderDraft?.firstIndex(where: { $0.id == header.id }) else { return }
            loadedState.customHeaderDraft?[index] = header
        default: break
        }
    }

    private func updateChatIDHeaderDraft(_ event: Event, in loadedState: inout LoadedState) {
        guard loadedState.customHeaderDraft != nil else { return }
        switch event {
        case .chatIDHeaderToggled(let enabled):
            loadedState.chatIDHeaderNameDraft = enabled ? (loadedState.chatIDHeaderNameDraft ?? "") : nil
        case .chatIDHeaderNameChanged(let name):
            guard loadedState.chatIDHeaderNameDraft != nil else { return }
            loadedState.chatIDHeaderNameDraft = name
        default: break
        }
    }

    private func applyCustomHeaderDraft(_ loadedState: inout LoadedState) {
        guard let draft = loadedState.customHeaderDraft,
              ServerHTTPHeader.validationError(in: draft, chatIDHeaderName: loadedState.chatIDHeaderNameDraft) == nil
        else { return }
        if draft != loadedState.customHeaders || loadedState.chatIDHeaderNameDraft != loadedState.chatIDHeaderName {
            loadedState.customHeaders = draft
            loadedState.chatIDHeaderName = loadedState.chatIDHeaderNameDraft
            markServerConfigurationEdited(&loadedState)
        }
        loadedState.customHeaderDraft = nil
        loadedState.chatIDHeaderNameDraft = nil
    }
}
