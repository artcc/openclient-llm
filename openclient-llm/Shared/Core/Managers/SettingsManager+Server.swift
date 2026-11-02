//
//  SettingsManager+Server.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 02/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

extension SettingsManager {
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

    func getCustomHeaders() -> [ServerHTTPHeader] {
        keychainManager.getCustomHeaders()
    }

    @discardableResult
    func setServerConfiguration(
        serverBaseURL: String, apiKey: String, customHeaders: [ServerHTTPHeader]
    ) -> Bool {
        guard ServerHTTPHeader.validationError(in: customHeaders) == nil else { return false }
        let previousURL = keychainManager.getServerBaseURL()
        let previousAPIKey = keychainManager.getAPIKey()
        let previousHeaders = keychainManager.getCustomHeaders()
        let endpointChanged = MCPToolInfo.normalizedServerURL(previousURL)
            != MCPToolInfo.normalizedServerURL(serverBaseURL)
        let credentialsChanged = previousAPIKey != apiKey
            || !ServerHTTPHeader.hasSameValues(previousHeaders, customHeaders)

        guard endpointChanged || credentialsChanged else {
            guard previousURL != serverBaseURL || previousHeaders != customHeaders else { return true }
            let didSave = keychainManager.setServerConfiguration(
                serverBaseURL: serverBaseURL, apiKey: apiKey, customHeaders: customHeaders
            )
            if didSave {
                NotificationCenter.default.post(name: .serverConfigurationDidChange, object: nil)
            }
            return didSave
        }
        guard rotateMCPAuthorizationScope() else { return false }
        _ = updateMCPToolConfigurationKeys([:])
        let didSave = keychainManager.setServerConfiguration(
            serverBaseURL: serverBaseURL, apiKey: apiKey, customHeaders: customHeaders
        )
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

    func rotateMCPAuthorizationScope() -> Bool {
        let scope = UUID().uuidString
        return keychainManager.setMCPAuthorizationScope(scope)
            && keychainManager.getMCPAuthorizationScope() == scope
    }
}
