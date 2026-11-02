//
//  KeychainManager.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

protocol KeychainManagerProtocol: Sendable {
    func getServerBaseURL() -> String
    func setServerBaseURL(_ value: String)
    func getAPIKey() -> String
    func setAPIKey(_ value: String)
    func getCustomHeaders() -> [ServerHTTPHeader]
    @discardableResult func setServerConfiguration(
        serverBaseURL: String, apiKey: String, customHeaders: [ServerHTTPHeader]
    ) -> Bool
    func getMCPAuthorizationScope() -> String?
    @discardableResult func setMCPAuthorizationScope(_ value: String) -> Bool
    func deleteAll()
}

extension KeychainManagerProtocol {
    @discardableResult
    func setServerConfiguration(serverBaseURL: String, apiKey: String) -> Bool {
        setServerConfiguration(serverBaseURL: serverBaseURL, apiKey: apiKey, customHeaders: getCustomHeaders())
    }
}

// Safety: All Keychain operations use thread-safe Security framework APIs.
// All stored properties are immutable (`let`).
final class KeychainManager: KeychainManagerProtocol, @unchecked Sendable {
    // MARK: - Properties

    private enum Keys {
        static let serverBaseURL = "com.openclient-llm.serverBaseURL"
        static let apiKey = "com.openclient-llm.apiKey"
        static let serverConfiguration = "com.openclient-llm.serverConfiguration"
        static let mcpAuthorizationScope = "com.openclient-llm.mcpAuthorizationScope"
    }

    private let service: String

    // MARK: - Init

    init(service: String = "com.openclient-llm") {
        self.service = service
    }

    // MARK: - Public

    func getServerBaseURL() -> String {
        getServerConfiguration().serverBaseURL
    }

    func setServerBaseURL(_ value: String) {
        _ = setServerConfiguration(serverBaseURL: value, apiKey: getAPIKey())
    }

    func getAPIKey() -> String {
        getServerConfiguration().apiKey
    }

    func setAPIKey(_ value: String) {
        _ = setServerConfiguration(serverBaseURL: getServerBaseURL(), apiKey: value)
    }

    @discardableResult
    func setServerConfiguration(
        serverBaseURL: String, apiKey: String, customHeaders: [ServerHTTPHeader]
    ) -> Bool {
        guard ServerHTTPHeader.validationError(in: customHeaders) == nil else { return false }
        let configuration = StoredServerConfiguration(
            serverBaseURL: serverBaseURL, apiKey: apiKey, customHeaders: customHeaders
        )
        guard let data = try? JSONEncoder().encode(configuration),
              setData(data, forKey: Keys.serverConfiguration) else { return false }
        deleteItem(forKey: Keys.serverBaseURL)
        deleteItem(forKey: Keys.apiKey)
        return true
    }

    func getCustomHeaders() -> [ServerHTTPHeader] {
        getServerConfiguration().customHeaders ?? []
    }

    func getMCPAuthorizationScope() -> String? {
        getString(forKey: Keys.mcpAuthorizationScope)
    }

    @discardableResult
    func setMCPAuthorizationScope(_ value: String) -> Bool {
        setString(value, forKey: Keys.mcpAuthorizationScope)
    }

    func deleteAll() {
        deleteItem(forKey: Keys.serverBaseURL)
        deleteItem(forKey: Keys.apiKey)
        deleteItem(forKey: Keys.serverConfiguration)
        deleteItem(forKey: Keys.mcpAuthorizationScope)
    }
}

// MARK: - Private

private extension KeychainManager {
    struct StoredServerConfiguration: Codable {
        let serverBaseURL: String
        let apiKey: String
        var customHeaders: [ServerHTTPHeader]?
    }

    func getServerConfiguration() -> StoredServerConfiguration {
        if let data = getData(forKey: Keys.serverConfiguration),
           let configuration = try? JSONDecoder().decode(StoredServerConfiguration.self, from: data) {
            return configuration
        }
        let legacyConfiguration = StoredServerConfiguration(
            serverBaseURL: getString(forKey: Keys.serverBaseURL) ?? "",
            apiKey: getString(forKey: Keys.apiKey) ?? ""
        )
        if !legacyConfiguration.serverBaseURL.isEmpty || !legacyConfiguration.apiKey.isEmpty {
            _ = setServerConfiguration(
                serverBaseURL: legacyConfiguration.serverBaseURL,
                apiKey: legacyConfiguration.apiKey,
                customHeaders: []
            )
        }
        return legacyConfiguration
    }

    func getString(forKey key: String) -> String? {
        guard let data = getData(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func getData(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return data
    }

    func setString(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return setData(data, forKey: key)
    }

    func setData(_ data: Data, forKey key: String) -> Bool {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true
        ]
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }
        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    func deleteItem(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true
        ]

        SecItemDelete(query as CFDictionary)
    }
}
