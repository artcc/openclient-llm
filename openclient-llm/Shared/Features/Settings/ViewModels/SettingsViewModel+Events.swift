//
//  SettingsViewModel+Events.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 10/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

extension SettingsViewModel {
    // MARK: - Input

    func send(_ event: Event) {
        switch event {
        case .cloudSyncToggled, .cloudSyncConflictResolved, .cloudSyncConflictCancelled,
             .syncNowTapped, .cloudSyncRetryTapped, .cloudAccountReviewConfirmed,
             .cloudAccountReviewCancelled, .cloudAccountReviewDismissed:
            handleCloudSyncEvent(event)
        case .showTokenUsageToggled, .privacyScreenToggled:
            handlePreferenceToggleEvent(event)
        case .appIconSelected(let icon):
            changeAppIcon(to: icon)
        case .modelConfigurationChanged(let configuration):
            guard case .loaded(var loadedState) = state else { return }
            settingsManager.setGlobalChatModelConfiguration(configuration)
            loadedState.modelConfiguration = settingsManager.getGlobalChatModelConfiguration()
            state = .loaded(loadedState)
        case .webSearchToolNameChanged, .webSearchMaxResultsChanged, .fetchSearchToolsTapped,
             .fetchMCPToolsTapped, .mcpToolToggled, .mcpToolsToggled,
             .mcpToolPermissionChanged, .mcpToolsPermissionChanged:
            handleServerDiscoveryEvent(event)
        default:
            handleCoreEvent(event)
        }
    }

    // MARK: - Private

    private func handleCoreEvent(_ event: Event) {
        switch event {
        case .viewAppeared:
            loadSettings()
        case .serverURLChanged(let url):
            updateServerURL(url)
        case .apiKeyChanged(let key):
            updateAPIKey(key)
        case .testConnectionTapped:
            testConnection()
        case .saveTapped:
            saveSettings()
        case .cloudAvailabilityRefresh:
            refreshCloudAvailability()
        case .resetConfirmed:
            resetApp()
        case .requestNotificationPermissionTapped, .notificationStatusRefresh:
            handleNotificationEvent(event)
        default:
            break
        }
    }

    private func requestNotificationPermission() {
        Task {
            await notificationPermissionUseCase.execute()
            refreshNotificationStatus()
        }
    }

    private func handleNotificationEvent(_ event: Event) {
        switch event {
        case .requestNotificationPermissionTapped:
            requestNotificationPermission()
        case .notificationStatusRefresh:
            refreshNotificationStatus()
        default:
            break
        }
    }

    private func handleServerDiscoveryEvent(_ event: Event) {
        handleWebSearchEvent(event)
        handleMCPEvent(event)
    }

    private func handleMCPEvent(_ event: Event) {
        switch event {
        case .fetchMCPToolsTapped:
            fetchMCPTools()
        case .mcpToolToggled(let toolId, let enabled):
            toggleMCPTool(toolId: toolId, enabled: enabled)
        case .mcpToolsToggled(let toolIds, let enabled):
            toggleMCPTools(toolIds: toolIds, enabled: enabled)
        case .mcpToolPermissionChanged(let toolId, let permission):
            updateMCPToolPermission(toolId: toolId, permission: permission)
        case .mcpToolsPermissionChanged(let toolIds, let permission):
            updateMCPToolPermissions(toolIds: toolIds, permission: permission)
        default:
            break
        }
    }

    func enabledMCPToolIds(savedIds: [String], tools: [MCPToolInfo]) -> Set<String> {
        MCPToolInfo.migratedEnabledToolIds(savedIds: savedIds, tools: tools)
    }

    private func changeAppIcon(to icon: AppIcon) {
        guard case .loaded(var loadedState) = state,
              loadedState.canChangeAppIcon,
              !loadedState.isChangingAppIcon,
              loadedState.selectedAppIcon != icon else { return }

        loadedState.isChangingAppIcon = true
        loadedState.appIconError = nil
        state = .loaded(loadedState)

        Task {
            do {
                try await appIconManager.setIcon(icon)
                guard case .loaded(var currentState) = state else { return }
                currentState.selectedAppIcon = icon
                currentState.isChangingAppIcon = false
                state = .loaded(currentState)
            } catch {
                LogManager.error("Unable to change app icon: \(error.localizedDescription)")
                guard case .loaded(var currentState) = state else { return }
                currentState.isChangingAppIcon = false
                currentState.appIconError = String(localized: "The app icon could not be changed. Please try again.")
                state = .loaded(currentState)
            }
        }
    }
}
