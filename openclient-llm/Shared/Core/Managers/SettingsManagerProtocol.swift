//
//  SettingsManagerProtocol.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 14/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

protocol SettingsManagerProtocol: Sendable {
    func getIsOnboardingCompleted() -> Bool
    func setIsOnboardingCompleted(_ value: Bool)
    func getServerBaseURL() -> String
    func setServerBaseURL(_ value: String)
    func getAPIKey() -> String
    func setAPIKey(_ value: String)
    @discardableResult func setServerConfiguration(serverBaseURL: String, apiKey: String) -> Bool
    func getMCPAuthorizationScope() -> String
    func getSelectedModelId() -> String?
    func setSelectedModelId(_ value: String?)
    func getIsCloudSyncEnabled() -> Bool
    func setIsCloudSyncEnabled(_ value: Bool)
    func getLastSuccessfulCloudSyncDate() -> Date?
    func setLastSuccessfulCloudSyncDate(_ value: Date)
    func getAcceptedCloudAccountFingerprint() -> String?
    func setAcceptedCloudAccountFingerprint(_ value: String)
    func getShowTokenUsage() -> Bool
    func setShowTokenUsage(_ value: Bool)
    func getIsWebSearchEnabled() -> Bool
    func setIsWebSearchEnabled(_ value: Bool)
    func getSelectedTTSModelId() -> String?
    func setSelectedTTSModelId(_ value: String?)
    func getSelectedTTSVoice(forModelId modelId: String) -> String
    func setSelectedTTSVoice(_ voice: String, forModelId modelId: String)
    func getSelectedSTTModelId() -> String?
    func setSelectedSTTModelId(_ value: String?)
    func getSelectedVisionModelId() -> String?
    func setSelectedVisionModelId(_ value: String?)
    func getSelectedImageGenerationModelId() -> String?
    func setSelectedImageGenerationModelId(_ value: String?)
    func getWebSearchToolName() -> String
    func setWebSearchToolName(_ value: String)
    func getWebSearchMaxResults() -> Int
    func setWebSearchMaxResults(_ value: Int)
    func getAvailableSearchTools() -> [SearchToolItem]
    func setAvailableSearchTools(_ tools: [SearchToolItem])
    func getIsPrivacyScreenEnabled() -> Bool
    func setIsPrivacyScreenEnabled(_ value: Bool)
    func getHasEnoughConversationsForMemoryTip() -> Bool
    func setHasEnoughConversationsForMemoryTip(_ value: Bool)
    func getIsBuiltInToolEnabled(_ tool: BuiltInTool) -> Bool
    func setIsBuiltInToolEnabled(_ value: Bool, for tool: BuiltInTool)
    func getEnabledMCPToolIds() -> [String]
    func setEnabledMCPToolIds(_ ids: [String])
    func getMCPToolPermissionRawValue(for key: String) -> String?
    func setMCPToolPermissionRawValue(_ value: String, for key: String)
    func setMCPToolPermissionRawValues(_ value: String, for keys: [String])
    func getMCPToolConfigurationKey(for toolId: String) -> String?
    func setMCPToolConfigurationKey(_ key: String, for toolId: String)
    func replaceMCPToolConfigurationKeys(_ keys: [String: String])
    func beginMCPToolDiscovery() -> Int
    func getPublishedMCPToolDiscoveryRevision() -> Int
    func getFailedMCPServerIds() -> Set<String>
    func getIsMCPDiscoveryFailed() -> Bool
    func publishMCPToolDiscoveryFailure(revision: Int) -> Bool
    func publishMCPToolDiscovery(
        revision: Int,
        configurationKeys: [String: String],
        enabledToolIds: [String],
        servers: [MCPServerInfo],
        failedServerIds: Set<String>
    ) -> Bool
    func getDismissedRemoteBannerKey() -> String?
    func setDismissedRemoteBannerKey(_ value: String?)
    func deleteAll()
}

extension SettingsManagerProtocol {
    func hasValidServerConfiguration() -> Bool {
        let serverURL = getServerBaseURL().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: serverURL),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false else {
            return false
        }
        return true
    }
}
