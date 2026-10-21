//
//  SettingsViewModel.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

@Observable
@MainActor
final class SettingsViewModel {
    // MARK: - Properties

    enum Event {
        case viewAppeared
        case serverURLChanged(String)
        case apiKeyChanged(String)
        case testConnectionTapped
        case saveTapped
        case cloudSyncToggled(Bool)
        case cloudSyncConflictResolved(keepLocal: Bool)
        case cloudSyncConflictCancelled
        case syncNowTapped
        case cloudSyncRetryTapped
        case cloudAccountReviewConfirmed
        case cloudAccountReviewCancelled
        case cloudAccountReviewDismissed
        case cloudAvailabilityRefresh
        case showTokenUsageToggled(Bool)
        case modelConfigurationChanged(ChatModelConfiguration)
        case webSearchToolNameChanged(String)
        case webSearchMaxResultsChanged(Int)
        case fetchSearchToolsTapped
        case resetConfirmed
        case requestNotificationPermissionTapped
        case notificationStatusRefresh
        case privacyScreenToggled(Bool)
        case fetchMCPToolsTapped
        case mcpToolToggled(toolId: String, enabled: Bool)
        case mcpToolsToggled(toolIds: [String], enabled: Bool)
        case mcpToolPermissionChanged(toolId: String, permission: MCPToolPermission)
        case mcpToolsPermissionChanged(toolIds: [String], permission: MCPToolPermission)
        case appIconSelected(AppIcon)
    }

    enum State: Equatable {
        case loading
        case loaded(LoadedState)
    }

    struct LoadedState: Equatable {
        var serverURL: String = ""
        var apiKey: String = ""
        var connectionStatus: ConnectionStatus = .idle
        var isSaved: Bool = false
        var serverPersistenceError: String?
        var serverPersistenceFailureCount: Int = 0
        var isCloudSyncEnabled: Bool = false
        var showTokenUsage: Bool = true
        var modelConfiguration: ChatModelConfiguration = .default
        var showCloudSyncConflictAlert: Bool = false
        var showCloudAccountReviewAlert: Bool = false
        var webSearchToolName: String = ""
        var webSearchMaxResults: Int = 10
        var availableSearchTools: [SearchToolItem] = []
        var isLoadingSearchTools: Bool = false
        var searchToolsError: String?
        var showLiteLLMHint: Bool = false
        var notificationPermissionStatus: NotificationPermissionStatus = .notDetermined
        var isPrivacyScreenEnabled: Bool = true
        var synchronizationResult: AppSynchronizationResult?
        var resetErrorMessage: String?
        var isTipJarEnabled: Bool = true
        var availableMCPTools: [MCPToolInfo] = []
        var availableMCPServers: [MCPServerInfo] = []
        var failedMCPServerIds: Set<String> = []
        var enabledMCPToolIds: Set<String> = []
        var mcpToolPermissions: [String: MCPToolPermission] = [:]
        var mcpDiscoveryScope: String?
        var mcpDiscoveryRevision: Int = 0
        var isLoadingMCPTools: Bool = false
        var mcpToolsError: String?
        var selectedAppIcon: AppIcon = .defaultIcon
        var canChangeAppIcon: Bool = false
        var isChangingAppIcon: Bool = false
        var appIconError: String?
        var visibleAppIconCategories: [AppIcon.Category] = AppIcon.Category.allCases
    }

    enum ConnectionStatus: Equatable {
        case idle
        case testing
        case success
        case failure(String)
    }

    var state: State

    var cloudSyncStatus: CloudSyncStatus {
        cloudSyncRuntimeStore.status
    }

    var lastSuccessfulCloudSyncAt: Date? {
        settingsManager.getLastSuccessfulCloudSyncDate()
    }

    private let saveServerConfigurationUseCase: SaveServerConfigurationUseCaseProtocol
    private let testServerConnectionUseCase: TestServerConnectionUseCaseProtocol
    private let checkLiteLLMHealthUseCase: CheckLiteLLMHealthUseCaseProtocol
    private let fetchSearchToolsUseCase: FetchSearchToolsUseCaseProtocol
    let fetchMCPToolsUseCase: FetchMCPToolsUseCaseProtocol
    let settingsManager: SettingsManagerProtocol
    let cloudSyncManager: CloudSyncManagerProtocol
    let synchronizeAppDataUseCase: SynchronizeAppDataUseCaseProtocol
    let cloudSyncCoordinator: CloudSyncRuntimeCoordinating
    let userProfileManager: UserProfileManagerProtocol
    let cloudSyncRuntimeStore: CloudSyncRuntimeStoreProtocol
    let cloudAccountAssociation: CloudAccountAssociationProtocol
    private let resetAppUseCase: ResetAppDataUseCaseProtocol
    private let checkNotificationPermissionUseCase: NotificationStatusCheckProtocol
    let notificationPermissionUseCase: NotificationPermissionUseCaseProtocol
    let appIconManager: AppIconManagerProtocol
    private let remoteConfigManager: RemoteConfigManagerProtocol
    var synchronizationTask: Task<Void, Never>?
    var cloudEnableTask: Task<Void, Never>?
    var cloudSyncGeneration = 0
    var mcpSettingsObservationTask: Task<Void, Never>?
    var mcpDiscoveryTask: Task<Void, Never>?
    var mcpDiscoveryGeneration = 0
    var observedMCPAuthorizationScope: String

    // MARK: - Init

    init(
        state: State = .loading,
        saveServerConfigurationUseCase: SaveServerConfigurationUseCaseProtocol = SaveServerConfigurationUseCase(),
        testServerConnectionUseCase: TestServerConnectionUseCaseProtocol = TestServerConnectionUseCase(),
        checkLiteLLMHealthUseCase: CheckLiteLLMHealthUseCaseProtocol = CheckLiteLLMHealthUseCase(),
        fetchSearchToolsUseCase: FetchSearchToolsUseCaseProtocol = FetchSearchToolsUseCase(),
        fetchMCPToolsUseCase: FetchMCPToolsUseCaseProtocol = FetchMCPToolsUseCase(),
        settingsManager: SettingsManagerProtocol = SettingsManager(),
        cloudSyncManager: CloudSyncManagerProtocol = CloudSyncManager(),
        synchronizeAppDataUseCase: SynchronizeAppDataUseCaseProtocol = SynchronizeAppDataUseCase(),
        cloudSyncCoordinator: CloudSyncRuntimeCoordinating = ConversationCloudObserver.shared,
        userProfileManager: UserProfileManagerProtocol = UserProfileManager(),
        cloudSyncRuntimeStore: CloudSyncRuntimeStoreProtocol = CloudSyncRuntimeStore.shared,
        cloudAccountAssociation: CloudAccountAssociationProtocol = CloudAccountAssociation.shared,
        resetAppUseCase: ResetAppDataUseCaseProtocol = ResetAppDataUseCase(),
        checkNotificationPermissionUseCase: NotificationStatusCheckProtocol = CheckNotificationPermissionUseCase(),
        notificationPermissionUseCase: NotificationPermissionUseCaseProtocol = NotificationPermissionUseCase(),
        appIconManager: AppIconManagerProtocol = AppIconManager(),
        remoteConfigManager: RemoteConfigManagerProtocol = RemoteConfigManager.shared
    ) {
        self.state = state
        self.saveServerConfigurationUseCase = saveServerConfigurationUseCase
        self.testServerConnectionUseCase = testServerConnectionUseCase
        self.checkLiteLLMHealthUseCase = checkLiteLLMHealthUseCase
        self.fetchSearchToolsUseCase = fetchSearchToolsUseCase
        self.fetchMCPToolsUseCase = fetchMCPToolsUseCase
        self.settingsManager = settingsManager
        self.observedMCPAuthorizationScope = settingsManager.getMCPAuthorizationScope()
        self.cloudSyncManager = cloudSyncManager
        self.synchronizeAppDataUseCase = synchronizeAppDataUseCase
        self.cloudSyncCoordinator = cloudSyncCoordinator
        self.userProfileManager = userProfileManager
        self.cloudSyncRuntimeStore = cloudSyncRuntimeStore
        self.cloudAccountAssociation = cloudAccountAssociation
        self.resetAppUseCase = resetAppUseCase
        self.checkNotificationPermissionUseCase = checkNotificationPermissionUseCase
        self.notificationPermissionUseCase = notificationPermissionUseCase
        self.appIconManager = appIconManager
        self.remoteConfigManager = remoteConfigManager
        observeMCPToolSettingsChanges()
    }

    isolated deinit {
        mcpSettingsObservationTask?.cancel()
        mcpDiscoveryTask?.cancel()
    }
}

// MARK: - Internal

extension SettingsViewModel {
    func loadSettings() {
#if DEBUG
        let savedServerURL = settingsManager.getServerBaseURL()
        let getServerBaseURL = savedServerURL.isEmpty ? Constants.URLs.serverUrl : savedServerURL
#else
        let getServerBaseURL = settingsManager.getServerBaseURL()
#endif
        let loadedState = LoadedState(
            serverURL: getServerBaseURL,
            apiKey: settingsManager.getAPIKey(),
            isCloudSyncEnabled: settingsManager.getIsCloudSyncEnabled(),
            showTokenUsage: settingsManager.getShowTokenUsage(),
            modelConfiguration: settingsManager.getGlobalChatModelConfiguration(),
            webSearchToolName: settingsManager.getWebSearchToolName(),
            webSearchMaxResults: settingsManager.getWebSearchMaxResults(),
            availableSearchTools: settingsManager.getAvailableSearchTools(),
            isPrivacyScreenEnabled: settingsManager.getIsPrivacyScreenEnabled(),
            isTipJarEnabled: remoteConfigManager.currentConfig?.isTipJarEnabled ?? true,
            enabledMCPToolIds: Set(settingsManager.getEnabledMCPToolIds()),
            selectedAppIcon: appIconManager.selectedIcon,
            canChangeAppIcon: appIconManager.supportsAlternateIcons,
            visibleAppIconCategories: AppIcon.Category.visibleCategories(
                showIconPacks: remoteConfigManager.currentConfig?.showIconPacks
            )
        )
        state = .loaded(loadedState)
        if loadedState.isCloudSyncEnabled {
            switch cloudAccountAssociation.state() {
            case .unassociated, .changed:
                cloudSyncRuntimeStore.publish(.failed(.init(
                    reason: .accountChanged,
                    affectedCategories: Set(CloudSyncStatus.DataCategory.allCases)
                )))
            case .unavailable, .matched:
                if cloudSyncRuntimeStore.status == .disabled {
                    cloudSyncRuntimeStore.publish(.checkingAvailability)
                }
            }
        } else if !loadedState.isCloudSyncEnabled {
            cloudSyncRuntimeStore.publish(.disabled)
        }
        let serverURL = loadedState.serverURL
        if !serverURL.isEmpty {
            Task {
                await updateLiteLLMHint(serverURL: serverURL)
            }
        }
        refreshNotificationStatus()
        fetchMCPTools()
    }

    func updateServerURL(_ url: String) {
        guard case .loaded(var loadedState) = state else { return }
        loadedState.serverURL = url
        loadedState.connectionStatus = .idle
        loadedState.isSaved = false
        loadedState.serverPersistenceError = nil
        state = .loaded(loadedState)
    }

    func updateAPIKey(_ key: String) {
        guard case .loaded(var loadedState) = state else { return }
        loadedState.apiKey = key
        loadedState.connectionStatus = .idle
        loadedState.isSaved = false
        loadedState.serverPersistenceError = nil
        state = .loaded(loadedState)
    }

    func testConnection() {
        guard case .loaded(var loadedState) = state else { return }
        let serverURL = loadedState.serverURL
        let apiKey = loadedState.apiKey
        LogManager.info("testConnection url=\(serverURL)")
        loadedState.connectionStatus = .testing
        state = .loaded(loadedState)

        Task {
            do {
                try await testServerConnectionUseCase.execute(serverURL: serverURL, apiKey: apiKey)
                guard case .loaded(var currentState) = state else { return }
                currentState.connectionStatus = .success
                state = .loaded(currentState)
                LogManager.success("testConnection success url=\(serverURL)")
            } catch {
                guard case .loaded(var currentState) = state else { return }
                currentState.connectionStatus = .failure(error.localizedDescription)
                state = .loaded(currentState)
                LogManager.error("testConnection failed url=\(serverURL): \(error)")
            }
            await updateLiteLLMHint(serverURL: serverURL)
        }
    }

    func saveSettings() {
        guard case .loaded(var loadedState) = state else { return }
        let serverURL = loadedState.serverURL
        let apiKey = loadedState.apiKey
        let configurationChanged = serverURL != settingsManager.getServerBaseURL()
            || apiKey != settingsManager.getAPIKey()
        LogManager.info("saveSettings url=\(serverURL)")
        guard saveServerConfigurationUseCase.execute(serverURL: serverURL, apiKey: apiKey) else {
            loadedState.isSaved = false
            loadedState.serverPersistenceFailureCount += 1
            loadedState.serverPersistenceError = String(localized: "The server configuration could not be saved.")
            state = .loaded(loadedState)
            return
        }
        loadedState.isSaved = true
        loadedState.serverPersistenceError = nil
        state = .loaded(loadedState)
        LogManager.success("saveSettings done")
        Task {
            await updateLiteLLMHint(serverURL: serverURL)
        }
        if configurationChanged { fetchMCPTools(replacingCurrent: true) }
    }

    func updateLiteLLMHint(serverURL: String) async {
        let isLiteLLM = await checkLiteLLMHealthUseCase.execute(serverURL: serverURL)
        guard case .loaded(var currentState) = state else { return }
        currentState.showLiteLLMHint = !isLiteLLM
        state = .loaded(currentState)
    }

    func toggleShowTokenUsage(_ show: Bool) {
        guard case .loaded(var loadedState) = state else { return }
        settingsManager.setShowTokenUsage(show)
        loadedState.showTokenUsage = show
        state = .loaded(loadedState)
    }

    func handlePreferenceToggleEvent(_ event: Event) {
        switch event {
        case .showTokenUsageToggled(let show):
            toggleShowTokenUsage(show)
        case .privacyScreenToggled(let enabled):
#if os(iOS)
            togglePrivacyScreen(enabled)
#else
            _ = enabled
#endif
        default:
            break
        }
    }

#if os(iOS)
    func togglePrivacyScreen(_ enabled: Bool) {
        guard case .loaded(var loadedState) = state else { return }
        settingsManager.setIsPrivacyScreenEnabled(enabled)
        loadedState.isPrivacyScreenEnabled = enabled
        state = .loaded(loadedState)
    }
#endif

    func updateWebSearchToolName(_ name: String) {
        guard case .loaded(var loadedState) = state else { return }
        settingsManager.setWebSearchToolName(name)
        loadedState.webSearchToolName = name
        state = .loaded(loadedState)
    }

    func updateWebSearchMaxResults(_ count: Int) {
        guard case .loaded(var loadedState) = state else { return }
        settingsManager.setWebSearchMaxResults(count)
        loadedState.webSearchMaxResults = count
        state = .loaded(loadedState)
    }

    func handleWebSearchEvent(_ event: Event) {
        switch event {
        case .webSearchToolNameChanged(let name):
            updateWebSearchToolName(name)
        case .webSearchMaxResultsChanged(let count):
            updateWebSearchMaxResults(count)
        case .fetchSearchToolsTapped:
            fetchSearchTools()
        default:
            break
        }
    }

    func fetchSearchTools() {
        guard case .loaded(var loadedState) = state else { return }
        loadedState.isLoadingSearchTools = true
        loadedState.searchToolsError = nil
        state = .loaded(loadedState)

        Task {
            do {
                let tools = try await fetchSearchToolsUseCase.execute()
                guard case .loaded(var currentState) = state else { return }
                settingsManager.setAvailableSearchTools(tools)
                currentState.availableSearchTools = tools
                currentState.isLoadingSearchTools = false
                // Auto-select the first tool if the current name doesn't match any returned tool
                if !tools.isEmpty,
                   !tools.contains(where: { $0.searchToolName == currentState.webSearchToolName }) {
                    let firstName = tools[0].searchToolName
                    settingsManager.setWebSearchToolName(firstName)
                    currentState.webSearchToolName = firstName
                }
                state = .loaded(currentState)
            } catch {
                guard case .loaded(var currentState) = state else { return }
                currentState.isLoadingSearchTools = false
                currentState.searchToolsError = error.localizedDescription
                state = .loaded(currentState)
                LogManager.error("FetchSearchTools failed: \(error)")
            }
        }
    }

    func resetApp() {
        guard case .loaded(var loadedState) = state else { return }
        loadedState.resetErrorMessage = nil
        state = .loaded(loadedState)
        Task {
            do {
                try await resetAppUseCase.execute()
                loadSettings()
                NotificationCenter.default.post(name: .appDataDidReset, object: nil)
            } catch {
                LogManager.error("App data reset failed")
                guard case .loaded(var currentState) = state else { return }
                currentState.resetErrorMessage = String(
                    localized: "App data could not be completely reset. Your remaining data was not discarded."
                )
                state = .loaded(currentState)
            }
        }
    }

    func refreshNotificationStatus() {
        Task {
            let status = await checkNotificationPermissionUseCase.execute()
            guard case .loaded(var currentState) = state else { return }
            currentState.notificationPermissionStatus = status
            state = .loaded(currentState)
        }
    }

}
