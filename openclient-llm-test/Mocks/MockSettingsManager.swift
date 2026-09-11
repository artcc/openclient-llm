//
//  MockSettingsManager.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation
@testable import openclient_llm

// Safety: Only used within serialized @MainActor test methods.
final class MockSettingsManager: SettingsManagerProtocol, @unchecked Sendable {
    // MARK: - Properties

    var isOnboardingCompleted: Bool = false
    var serverBaseURL: String = ""
    var apiKey: String = ""
    var mcpAuthorizationScope: String = "test-scope"
    var selectedModelId: String?
    var selectedTTSModelId: String?
    var selectedSTTModelId: String?
    var selectedVisionModelId: String?
    var selectedImageGenerationModelId: String?
    var ttsVoices: [String: String] = [:]
    var isCloudSyncEnabled: Bool = false
    var lastSuccessfulCloudSyncDate: Date?
    var acceptedCloudAccountFingerprint: String?
    var showTokenUsage: Bool = true
    var isWebSearchEnabled: Bool = false
    var webSearchToolName: String = "brave-search"
    var webSearchMaxResults: Int = 10
    var availableSearchTools: [SearchToolItem] = []
    var isPrivacyScreenEnabled: Bool = true
    var hasEnoughConversationsForMemoryTip: Bool = false
    var disabledBuiltInTools: Set<BuiltInTool> = []
    var enabledMCPToolIds: [String] = []
    var enabledMCPToolWriteCount = 0
    var mcpToolPermissions: [String: MCPToolPermission] = [:]
    var mcpPermissionBatchWriteCount = 0
    var mcpToolConfigurationKeys: [String: String] = [:]
    var mcpDiscoverySequence = 0
    var publishedMCPDiscoverySequence = 0
    var publishedFailedMCPServerIds: Set<String> = []
    var mcpDiscoveryFailed = false
    var dismissedRemoteBannerKey: String?
    var deleteAllCalled: Bool = false

    // MARK: - Public

    func getIsOnboardingCompleted() -> Bool {
        isOnboardingCompleted
    }

    func setIsOnboardingCompleted(_ value: Bool) {
        isOnboardingCompleted = value
    }

    func getServerBaseURL() -> String {
        serverBaseURL
    }

    func setServerBaseURL(_ value: String) {
        if serverBaseURL != value { mcpAuthorizationScope = UUID().uuidString }
        serverBaseURL = value
    }

    func getAPIKey() -> String {
        apiKey
    }

    func setAPIKey(_ value: String) {
        if apiKey != value { mcpAuthorizationScope = UUID().uuidString }
        apiKey = value
    }

    @discardableResult
    func setServerConfiguration(serverBaseURL: String, apiKey: String) -> Bool {
        let endpointChanged = MCPToolInfo.normalizedServerURL(self.serverBaseURL)
            != MCPToolInfo.normalizedServerURL(serverBaseURL)
        if endpointChanged || self.apiKey != apiKey {
            mcpAuthorizationScope = UUID().uuidString
        }
        self.serverBaseURL = serverBaseURL
        self.apiKey = apiKey
        return true
    }

    func getMCPAuthorizationScope() -> String {
        mcpAuthorizationScope
    }

    func getSelectedModelId() -> String? {
        selectedModelId
    }

    func setSelectedModelId(_ value: String?) {
        selectedModelId = value
    }

    func getIsCloudSyncEnabled() -> Bool {
        isCloudSyncEnabled
    }

    func setIsCloudSyncEnabled(_ value: Bool) {
        isCloudSyncEnabled = value
    }

    func getLastSuccessfulCloudSyncDate() -> Date? {
        lastSuccessfulCloudSyncDate
    }

    func setLastSuccessfulCloudSyncDate(_ value: Date) {
        lastSuccessfulCloudSyncDate = value
    }

    func getAcceptedCloudAccountFingerprint() -> String? {
        acceptedCloudAccountFingerprint
    }

    func setAcceptedCloudAccountFingerprint(_ value: String) {
        acceptedCloudAccountFingerprint = value
    }

    func getShowTokenUsage() -> Bool {
        showTokenUsage
    }

    func setShowTokenUsage(_ value: Bool) {
        showTokenUsage = value
    }

    func getIsWebSearchEnabled() -> Bool {
        isWebSearchEnabled
    }

    func setIsWebSearchEnabled(_ value: Bool) {
        isWebSearchEnabled = value
    }

    func getSelectedTTSModelId() -> String? {
        selectedTTSModelId
    }

    func setSelectedTTSModelId(_ value: String?) {
        selectedTTSModelId = value
    }

    func getSelectedTTSVoice(forModelId modelId: String) -> String {
        ttsVoices[modelId] ?? TTSVoice.alloy.rawValue
    }

    func setSelectedTTSVoice(_ voice: String, forModelId modelId: String) {
        ttsVoices[modelId] = voice
    }

    func getSelectedSTTModelId() -> String? {
        selectedSTTModelId
    }

    func setSelectedSTTModelId(_ value: String?) {
        selectedSTTModelId = value
    }

    func getSelectedVisionModelId() -> String? {
        selectedVisionModelId
    }

    func setSelectedVisionModelId(_ value: String?) {
        selectedVisionModelId = value
    }

    func getSelectedImageGenerationModelId() -> String? {
        selectedImageGenerationModelId
    }

    func setSelectedImageGenerationModelId(_ value: String?) {
        selectedImageGenerationModelId = value
    }

    func getWebSearchToolName() -> String {
        webSearchToolName
    }

    func setWebSearchToolName(_ value: String) {
        webSearchToolName = value
    }

    func getWebSearchMaxResults() -> Int {
        webSearchMaxResults
    }

    func setWebSearchMaxResults(_ value: Int) {
        webSearchMaxResults = value
    }

    func getAvailableSearchTools() -> [SearchToolItem] {
        availableSearchTools
    }

    func setAvailableSearchTools(_ tools: [SearchToolItem]) {
        availableSearchTools = tools
    }

    func getIsPrivacyScreenEnabled() -> Bool {
        isPrivacyScreenEnabled
    }

    func setIsPrivacyScreenEnabled(_ value: Bool) {
        isPrivacyScreenEnabled = value
    }

    func getHasEnoughConversationsForMemoryTip() -> Bool {
        hasEnoughConversationsForMemoryTip
    }

    func setHasEnoughConversationsForMemoryTip(_ value: Bool) {
        hasEnoughConversationsForMemoryTip = value
    }

    func getEnabledMCPToolIds() -> [String] {
        enabledMCPToolIds
    }

    func getIsBuiltInToolEnabled(_ tool: BuiltInTool) -> Bool {
        !disabledBuiltInTools.contains(tool)
    }

    func setIsBuiltInToolEnabled(_ value: Bool, for tool: BuiltInTool) {
        if value {
            disabledBuiltInTools.remove(tool)
        } else {
            disabledBuiltInTools.insert(tool)
        }
    }

    func setEnabledMCPToolIds(_ ids: [String]) {
        enabledMCPToolWriteCount += 1
        enabledMCPToolIds = ids
    }

    func getMCPToolPermissionRawValue(for key: String) -> String? {
        mcpToolPermissions[key]?.rawValue
    }

    func setMCPToolPermissionRawValue(_ value: String, for key: String) {
        mcpToolPermissions[key] = MCPToolPermission(rawValue: value)
    }

    func setMCPToolPermissionRawValues(_ value: String, for keys: [String]) {
        mcpPermissionBatchWriteCount += 1
        for key in Set(keys) {
            mcpToolPermissions[key] = MCPToolPermission(rawValue: value)
        }
    }

    func getMCPToolConfigurationKey(for toolId: String) -> String? {
        mcpToolConfigurationKeys[toolId]
    }

    func setMCPToolConfigurationKey(_ key: String, for toolId: String) {
        mcpToolConfigurationKeys[toolId] = key
    }

    func replaceMCPToolConfigurationKeys(_ keys: [String: String]) {
        mcpToolConfigurationKeys = keys
    }

    func beginMCPToolDiscovery() -> Int {
        mcpDiscoverySequence += 1
        return mcpDiscoverySequence
    }

    func getPublishedMCPToolDiscoveryRevision() -> Int {
        publishedMCPDiscoverySequence
    }

    func getFailedMCPServerIds() -> Set<String> {
        publishedFailedMCPServerIds
    }

    func getIsMCPDiscoveryFailed() -> Bool {
        mcpDiscoveryFailed
    }

    func publishMCPToolDiscoveryFailure(revision: Int) -> Bool {
        guard revision > publishedMCPDiscoverySequence else { return false }
        publishedMCPDiscoverySequence = revision
        mcpDiscoveryFailed = true
        return true
    }

    func publishMCPToolDiscovery(
        revision: Int,
        configurationKeys: [String: String],
        enabledToolIds: [String],
        servers: [MCPServerInfo],
        failedServerIds: Set<String>
    ) -> Bool {
        guard revision > publishedMCPDiscoverySequence else { return false }
        let publication = MCPToolDiscoveryPublication.merging(
            existingConfigurationKeys: mcpToolConfigurationKeys,
            existingEnabledToolIds: enabledMCPToolIds,
            discoveredConfigurationKeys: configurationKeys,
            discoveredEnabledToolIds: enabledToolIds,
            serverState: MCPDiscoveryServerState(servers: servers, failedServerIds: failedServerIds)
        )
        mcpToolConfigurationKeys = publication.configurationKeys
        enabledMCPToolIds = publication.enabledToolIds
        publishedMCPDiscoverySequence = revision
        publishedFailedMCPServerIds = failedServerIds
        mcpDiscoveryFailed = false
        return true
    }

    func getDismissedRemoteBannerKey() -> String? {
        dismissedRemoteBannerKey
    }

    func setDismissedRemoteBannerKey(_ value: String?) {
        dismissedRemoteBannerKey = value
    }

    func deleteAll() {
        isOnboardingCompleted = false
        serverBaseURL = ""
        apiKey = ""
        selectedModelId = nil
        selectedTTSModelId = nil
        selectedSTTModelId = nil
        selectedVisionModelId = nil
        selectedImageGenerationModelId = nil
        lastSuccessfulCloudSyncDate = nil
        acceptedCloudAccountFingerprint = nil
        ttsVoices = [:]
        enabledMCPToolIds = []
        mcpToolPermissions = [:]
        mcpToolConfigurationKeys = [:]
        mcpDiscoverySequence = 0
        publishedMCPDiscoverySequence = 0
        publishedFailedMCPServerIds = []
        mcpDiscoveryFailed = false
        mcpAuthorizationScope = UUID().uuidString
        hasEnoughConversationsForMemoryTip = false
        disabledBuiltInTools = []
        dismissedRemoteBannerKey = nil
        deleteAllCalled = true
    }
}
