//
//  SettingsManager.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

// Safety: UserDefaults is thread-safe per Apple documentation.
// All stored properties are immutable (`let`).
final class SettingsManager: SettingsManagerProtocol, @unchecked Sendable {
    // MARK: - Properties

    private enum Keys {
        static let isOnboardingCompleted = "isOnboardingCompleted"
        static let selectedModelId = "selectedModelId"
        static let isCloudSyncEnabled = "isCloudSyncEnabled"
        static let lastSuccessfulCloudSyncDate = "lastSuccessfulCloudSyncDate"
        static let acceptedCloudAccountFingerprint = "acceptedCloudAccountFingerprint"
        static let showTokenUsage = "showTokenUsage"
        static let isWebSearchEnabled = "isWebSearchEnabled"
        static let selectedTTSModelId = "selectedTTSModelId"
        static let selectedSTTModelId = "selectedSTTModelId"
        static let selectedVisionModelId = "selectedVisionModelId"
        static let selectedImageGenerationModelId = "selectedImageGenerationModelId"
        static let webSearchToolName = "webSearchToolName"
        static let webSearchMaxResults = "webSearchMaxResults"
        static let availableSearchTools = "availableSearchTools"
        static let isPrivacyScreenEnabled = "isPrivacyScreenEnabled"
        static let hasEnoughConversationsForMemoryTip = "hasEnoughConversationsForMemoryTip"
        static let builtInToolEnabledPrefix = "builtInToolEnabled."
        static let enabledMCPToolIds = "enabledMCPToolIds"
        static let mcpToolPermissionPrefix = "mcpToolPermission."
        static let mcpToolConfigurationPrefix = "mcpToolConfiguration."
        static let mcpDiscoverySequence = "mcpDiscoverySequence"
        static let publishedMCPDiscoverySequence = "publishedMCPDiscoverySequence"
        static let failedMCPServerIds = "failedMCPServerIds"
        static let mcpDiscoveryFailed = "mcpDiscoveryFailed"
        static let dismissedRemoteBannerKey = "dismissedRemoteBannerKey"

        static func ttsVoiceKey(forModelId modelId: String) -> String {
            "tts_voice_\(modelId)"
        }
    }

    private enum LegacyKeys {
        static let serverBaseURL = "serverBaseURL"
        static let apiKey = "apiKey"
    }

    private let defaults: UserDefaults
    private let keychainManager: KeychainManagerProtocol

    // MARK: - Init

    init(
        defaults: UserDefaults = .standard,
        keychainManager: KeychainManagerProtocol = KeychainManager()
    ) {
        self.defaults = defaults
        self.keychainManager = keychainManager

        migrateToKeychain()
    }

    // MARK: - Public

    func getIsOnboardingCompleted() -> Bool {
        defaults.bool(forKey: Keys.isOnboardingCompleted)
    }

    func setIsOnboardingCompleted(_ value: Bool) {
        defaults.set(value, forKey: Keys.isOnboardingCompleted)
    }

    func getServerBaseURL() -> String {
        keychainManager.getServerBaseURL()
    }

    func setServerBaseURL(_ value: String) {
        _ = setServerConfiguration(serverBaseURL: value, apiKey: keychainManager.getAPIKey())
    }

    func getAPIKey() -> String {
        keychainManager.getAPIKey()
    }

    func setAPIKey(_ value: String) {
        _ = setServerConfiguration(serverBaseURL: keychainManager.getServerBaseURL(), apiKey: value)
    }

    @discardableResult
    func setServerConfiguration(serverBaseURL: String, apiKey: String) -> Bool {
        let previousURL = keychainManager.getServerBaseURL()
        let previousAPIKey = keychainManager.getAPIKey()
        let endpointChanged = MCPToolInfo.normalizedServerURL(previousURL)
            != MCPToolInfo.normalizedServerURL(serverBaseURL)
        let credentialsChanged = previousAPIKey != apiKey

        guard endpointChanged || credentialsChanged else {
            guard previousURL != serverBaseURL else { return true }
            let didSave = keychainManager.setServerConfiguration(serverBaseURL: serverBaseURL, apiKey: apiKey)
            if didSave {
                NotificationCenter.default.post(name: .serverConfigurationDidChange, object: nil)
            }
            return didSave
        }
        guard rotateMCPAuthorizationScope() else { return false }
        _ = updateMCPToolConfigurationKeys([:])
        let didSave = keychainManager.setServerConfiguration(serverBaseURL: serverBaseURL, apiKey: apiKey)
        NotificationCenter.default.post(name: .mcpToolSettingsDidChange, object: nil)
        if didSave {
            NotificationCenter.default.post(name: .serverConfigurationDidChange, object: nil)
        }
        return didSave
    }

    func getMCPAuthorizationScope() -> String {
        if let scope = keychainManager.getMCPAuthorizationScope() { return scope }
        let scope = UUID().uuidString
        guard keychainManager.setMCPAuthorizationScope(scope),
              keychainManager.getMCPAuthorizationScope() == scope else { return "" }
        return scope
    }

    func getSelectedModelId() -> String? {
        defaults.string(forKey: Keys.selectedModelId)
    }

    func setSelectedModelId(_ value: String?) {
        defaults.set(value, forKey: Keys.selectedModelId)
    }

    func getIsCloudSyncEnabled() -> Bool {
        defaults.bool(forKey: Keys.isCloudSyncEnabled)
    }

    func setIsCloudSyncEnabled(_ value: Bool) {
        guard defaults.bool(forKey: Keys.isCloudSyncEnabled) != value else { return }
        defaults.set(value, forKey: Keys.isCloudSyncEnabled)
        NotificationCenter.default.post(name: .cloudSyncIntentDidChange, object: nil)
    }

    func getLastSuccessfulCloudSyncDate() -> Date? {
        defaults.object(forKey: Keys.lastSuccessfulCloudSyncDate) as? Date
    }

    func setLastSuccessfulCloudSyncDate(_ value: Date) {
        defaults.set(value, forKey: Keys.lastSuccessfulCloudSyncDate)
    }

    func getAcceptedCloudAccountFingerprint() -> String? {
        defaults.string(forKey: Keys.acceptedCloudAccountFingerprint)
    }

    func setAcceptedCloudAccountFingerprint(_ value: String) {
        let isLowercaseSHA256 = value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
        guard isLowercaseSHA256 else { return }
        defaults.set(value, forKey: Keys.acceptedCloudAccountFingerprint)
    }

    func getShowTokenUsage() -> Bool {
        defaults.object(forKey: Keys.showTokenUsage) == nil ? true : defaults.bool(forKey: Keys.showTokenUsage)
    }

    func setShowTokenUsage(_ value: Bool) {
        defaults.set(value, forKey: Keys.showTokenUsage)
    }

    func getIsWebSearchEnabled() -> Bool {
        defaults.bool(forKey: Keys.isWebSearchEnabled)
    }

    func setIsWebSearchEnabled(_ value: Bool) {
        defaults.set(value, forKey: Keys.isWebSearchEnabled)
    }

    func getSelectedTTSModelId() -> String? {
        defaults.string(forKey: Keys.selectedTTSModelId)
    }

    func setSelectedTTSModelId(_ value: String?) {
        defaults.set(value, forKey: Keys.selectedTTSModelId)
    }

    func getSelectedTTSVoice(forModelId modelId: String) -> String {
        defaults.string(forKey: Keys.ttsVoiceKey(forModelId: modelId)) ?? TTSVoice.alloy.rawValue
    }

    func setSelectedTTSVoice(_ voice: String, forModelId modelId: String) {
        defaults.set(voice, forKey: Keys.ttsVoiceKey(forModelId: modelId))
    }

    func getSelectedSTTModelId() -> String? {
        defaults.string(forKey: Keys.selectedSTTModelId)
    }

    func setSelectedSTTModelId(_ value: String?) {
        defaults.set(value, forKey: Keys.selectedSTTModelId)
    }

    func getSelectedVisionModelId() -> String? {
        defaults.string(forKey: Keys.selectedVisionModelId)
    }

    func setSelectedVisionModelId(_ value: String?) {
        defaults.set(value, forKey: Keys.selectedVisionModelId)
    }

    func getSelectedImageGenerationModelId() -> String? {
        defaults.string(forKey: Keys.selectedImageGenerationModelId)
    }

    func setSelectedImageGenerationModelId(_ value: String?) {
        defaults.set(value, forKey: Keys.selectedImageGenerationModelId)
    }

    func getWebSearchToolName() -> String {
        defaults.string(forKey: Keys.webSearchToolName) ?? ""
    }

    func setWebSearchToolName(_ value: String) {
        defaults.set(value, forKey: Keys.webSearchToolName)
    }

    func getWebSearchMaxResults() -> Int {
        let stored = defaults.integer(forKey: Keys.webSearchMaxResults)
        return stored > 0 ? stored : 10
    }

    func setWebSearchMaxResults(_ value: Int) {
        defaults.set(value, forKey: Keys.webSearchMaxResults)
    }

    func getAvailableSearchTools() -> [SearchToolItem] {
        guard let data = defaults.data(forKey: Keys.availableSearchTools),
              let tools = try? JSONDecoder().decode([SearchToolItem].self, from: data) else {
            return []
        }
        return tools
    }

    func setAvailableSearchTools(_ tools: [SearchToolItem]) {
        guard let data = try? JSONEncoder().encode(tools) else { return }
        defaults.set(data, forKey: Keys.availableSearchTools)
    }

    func getIsPrivacyScreenEnabled() -> Bool {
        let stored = defaults.object(forKey: Keys.isPrivacyScreenEnabled)
        return stored == nil ? true : defaults.bool(forKey: Keys.isPrivacyScreenEnabled)
    }

    func setIsPrivacyScreenEnabled(_ value: Bool) {
        defaults.set(value, forKey: Keys.isPrivacyScreenEnabled)
    }

    func getHasEnoughConversationsForMemoryTip() -> Bool {
        defaults.bool(forKey: Keys.hasEnoughConversationsForMemoryTip)
    }

    func setHasEnoughConversationsForMemoryTip(_ value: Bool) {
        defaults.set(value, forKey: Keys.hasEnoughConversationsForMemoryTip)
    }

    func getDismissedRemoteBannerKey() -> String? {
        defaults.string(forKey: Keys.dismissedRemoteBannerKey)
    }

    func setDismissedRemoteBannerKey(_ value: String?) {
        defaults.set(value, forKey: Keys.dismissedRemoteBannerKey)
    }

    func deleteAll() {
        let wasCloudSyncEnabled = getIsCloudSyncEnabled()
        defaults.removeObject(forKey: Keys.isOnboardingCompleted)
        defaults.removeObject(forKey: Keys.selectedModelId)
        defaults.removeObject(forKey: Keys.isCloudSyncEnabled)
        defaults.removeObject(forKey: Keys.lastSuccessfulCloudSyncDate)
        defaults.removeObject(forKey: Keys.acceptedCloudAccountFingerprint)
        defaults.removeObject(forKey: Keys.showTokenUsage)
        defaults.removeObject(forKey: Keys.isWebSearchEnabled)
        defaults.removeObject(forKey: Keys.selectedTTSModelId)
        defaults.removeObject(forKey: Keys.selectedSTTModelId)
        defaults.removeObject(forKey: Keys.selectedVisionModelId)
        defaults.removeObject(forKey: Keys.selectedImageGenerationModelId)
        defaults.removeObject(forKey: Keys.webSearchToolName)
        defaults.removeObject(forKey: Keys.webSearchMaxResults)
        defaults.removeObject(forKey: Keys.availableSearchTools)
        defaults.removeObject(forKey: Keys.isPrivacyScreenEnabled)
        defaults.removeObject(forKey: Keys.hasEnoughConversationsForMemoryTip)
        for tool in BuiltInTool.allCases {
            defaults.removeObject(forKey: Keys.builtInToolEnabledPrefix + tool.rawValue)
        }
        defaults.removeObject(forKey: Keys.enabledMCPToolIds)
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Keys.mcpToolPermissionPrefix) {
            defaults.removeObject(forKey: key)
        }
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Keys.mcpToolConfigurationPrefix) {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: Keys.mcpDiscoverySequence)
        defaults.removeObject(forKey: Keys.publishedMCPDiscoverySequence)
        defaults.removeObject(forKey: Keys.failedMCPServerIds)
        defaults.removeObject(forKey: Keys.mcpDiscoveryFailed)
        defaults.removeObject(forKey: Keys.dismissedRemoteBannerKey)
        defaults.removeObject(forKey: LegacyKeys.serverBaseURL)
        defaults.removeObject(forKey: LegacyKeys.apiKey)
        keychainManager.deleteAll()
        NotificationCenter.default.post(name: .builtInToolSettingsDidChange, object: nil)
        NotificationCenter.default.post(name: .serverConfigurationDidChange, object: nil)
        if wasCloudSyncEnabled {
            NotificationCenter.default.post(name: .cloudSyncIntentDidChange, object: nil)
        }
    }

    func getIsBuiltInToolEnabled(_ tool: BuiltInTool) -> Bool {
        let key = Keys.builtInToolEnabledPrefix + tool.rawValue
        return defaults.object(forKey: key) == nil ? true : defaults.bool(forKey: key)
    }

    func setIsBuiltInToolEnabled(_ value: Bool, for tool: BuiltInTool) {
        guard getIsBuiltInToolEnabled(tool) != value else { return }
        defaults.set(value, forKey: Keys.builtInToolEnabledPrefix + tool.rawValue)
        NotificationCenter.default.post(name: .builtInToolSettingsDidChange, object: nil)
    }
}

// MARK: - MCP settings

extension SettingsManager {
    func getEnabledMCPToolIds() -> [String] {
        defaults.stringArray(forKey: Keys.enabledMCPToolIds) ?? []
    }

    func setEnabledMCPToolIds(_ ids: [String]) {
        guard updateEnabledMCPToolIds(ids) else { return }
        NotificationCenter.default.post(name: .mcpToolSettingsDidChange, object: nil)
    }

    func getMCPToolPermissionRawValue(for key: String) -> String? {
        defaults.string(forKey: Keys.mcpToolPermissionPrefix + key)
    }

    func setMCPToolPermissionRawValue(_ value: String, for key: String) {
        setMCPToolPermissionRawValues(value, for: [key])
    }

    func setMCPToolPermissionRawValues(_ value: String, for keys: [String]) {
        let changedKeys = Set(keys).filter {
            defaults.string(forKey: Keys.mcpToolPermissionPrefix + $0) != value
        }
        guard !changedKeys.isEmpty else { return }
        for key in changedKeys {
            defaults.set(value, forKey: Keys.mcpToolPermissionPrefix + key)
        }
        NotificationCenter.default.post(name: .mcpToolSettingsDidChange, object: nil)
    }

    func getMCPToolConfigurationKey(for toolId: String) -> String? {
        defaults.string(forKey: Keys.mcpToolConfigurationPrefix + toolId)
    }

    func setMCPToolConfigurationKey(_ key: String, for toolId: String) {
        let storageKey = Keys.mcpToolConfigurationPrefix + toolId
        guard defaults.string(forKey: storageKey) != key else { return }
        defaults.set(key, forKey: storageKey)
        NotificationCenter.default.post(name: .mcpToolSettingsDidChange, object: nil)
    }

    func replaceMCPToolConfigurationKeys(_ keys: [String: String]) {
        guard updateMCPToolConfigurationKeys(keys) else { return }
        NotificationCenter.default.post(name: .mcpToolSettingsDidChange, object: nil)
    }

    func beginMCPToolDiscovery() -> Int {
        let currentRevision = max(
            defaults.integer(forKey: Keys.mcpDiscoverySequence),
            defaults.integer(forKey: Keys.publishedMCPDiscoverySequence)
        )
        let revision = currentRevision + 1
        defaults.set(revision, forKey: Keys.mcpDiscoverySequence)
        return revision
    }

    func getPublishedMCPToolDiscoveryRevision() -> Int {
        defaults.integer(forKey: Keys.publishedMCPDiscoverySequence)
    }

    func getFailedMCPServerIds() -> Set<String> {
        Set(defaults.stringArray(forKey: Keys.failedMCPServerIds) ?? [])
    }

    func getIsMCPDiscoveryFailed() -> Bool {
        defaults.bool(forKey: Keys.mcpDiscoveryFailed)
    }

    func publishMCPToolDiscoveryFailure(revision: Int) -> Bool {
        let publishedRevision = defaults.integer(forKey: Keys.publishedMCPDiscoverySequence)
        guard revision > publishedRevision else { return false }
        let failureChanged = !defaults.bool(forKey: Keys.mcpDiscoveryFailed)
        defaults.set(true, forKey: Keys.mcpDiscoveryFailed)
        defaults.set(revision, forKey: Keys.publishedMCPDiscoverySequence)
        if failureChanged {
            NotificationCenter.default.post(name: .mcpToolSettingsDidChange, object: nil)
        }
        return true
    }

    func publishMCPToolDiscovery(
        revision: Int,
        configurationKeys: [String: String],
        enabledToolIds: [String],
        servers: [MCPServerInfo],
        failedServerIds: Set<String>
    ) -> Bool {
        let publishedRevision = defaults.integer(forKey: Keys.publishedMCPDiscoverySequence)
        guard revision > publishedRevision else { return false }
        let publication = MCPToolDiscoveryPublication.merging(
            existingConfigurationKeys: currentMCPToolConfigurationKeys(),
            existingEnabledToolIds: getEnabledMCPToolIds(),
            discoveredConfigurationKeys: configurationKeys,
            discoveredEnabledToolIds: enabledToolIds,
            serverState: MCPDiscoveryServerState(servers: servers, failedServerIds: failedServerIds)
        )
        let configurationChanged = updateMCPToolConfigurationKeys(publication.configurationKeys)
        let enabledToolsChanged = updateEnabledMCPToolIds(publication.enabledToolIds)
        let previousFailedServerIds = getFailedMCPServerIds()
        let failedServersChanged = previousFailedServerIds != failedServerIds
            || defaults.bool(forKey: Keys.mcpDiscoveryFailed)
        defaults.set(failedServerIds.sorted(), forKey: Keys.failedMCPServerIds)
        defaults.set(false, forKey: Keys.mcpDiscoveryFailed)
        defaults.set(revision, forKey: Keys.publishedMCPDiscoverySequence)
        if configurationChanged || enabledToolsChanged || failedServersChanged {
            NotificationCenter.default.post(name: .mcpToolSettingsDidChange, object: nil)
        }
        return true
    }
}

// MARK: - Private

private extension SettingsManager {
    func currentMCPToolConfigurationKeys() -> [String: String] {
        defaults.dictionaryRepresentation().reduce(into: [String: String]()) { result, entry in
            guard entry.key.hasPrefix(Keys.mcpToolConfigurationPrefix),
                  let value = entry.value as? String else { return }
            let toolId = String(entry.key.dropFirst(Keys.mcpToolConfigurationPrefix.count))
            result[toolId] = value
        }
    }

    func updateEnabledMCPToolIds(_ ids: [String]) -> Bool {
        guard Set(getEnabledMCPToolIds()) != Set(ids) else { return false }
        defaults.set(ids.sorted(), forKey: Keys.enabledMCPToolIds)
        return true
    }

    func updateMCPToolConfigurationKeys(_ keys: [String: String]) -> Bool {
        let existingStorageKeys = defaults.dictionaryRepresentation().keys.filter {
            $0.hasPrefix(Keys.mcpToolConfigurationPrefix)
        }
        let desiredStorageKeys = Set(keys.keys.map { Keys.mcpToolConfigurationPrefix + $0 })
        var didChange = false

        for storageKey in existingStorageKeys where !desiredStorageKeys.contains(storageKey) {
            defaults.removeObject(forKey: storageKey)
            didChange = true
        }
        for (toolId, key) in keys {
            let storageKey = Keys.mcpToolConfigurationPrefix + toolId
            guard defaults.string(forKey: storageKey) != key else { continue }
            defaults.set(key, forKey: storageKey)
            didChange = true
        }
        return didChange
    }

    func rotateMCPAuthorizationScope() -> Bool {
        let scope = UUID().uuidString
        return keychainManager.setMCPAuthorizationScope(scope)
            && keychainManager.getMCPAuthorizationScope() == scope
    }

    func migrateToKeychain() {
        let legacyURL = defaults.string(forKey: LegacyKeys.serverBaseURL)
        let legacyKey = defaults.string(forKey: LegacyKeys.apiKey)
        guard legacyURL != nil || legacyKey != nil else { return }
        let didMigrate = keychainManager.setServerConfiguration(
            serverBaseURL: legacyURL ?? keychainManager.getServerBaseURL(),
            apiKey: legacyKey ?? keychainManager.getAPIKey()
        )
        guard didMigrate else { return }
        defaults.removeObject(forKey: LegacyKeys.serverBaseURL)
        defaults.removeObject(forKey: LegacyKeys.apiKey)
    }
}
