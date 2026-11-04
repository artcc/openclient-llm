//
//  MockKeychainManager.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation
@testable import openclient_llm

// Safety: Only used within serialized @MainActor test methods.
final class MockKeychainManager: KeychainManagerProtocol, @unchecked Sendable {
    // MARK: - Properties

    var serverBaseURL: String = ""
    var apiKey: String = ""
    var customHeaders: [ServerHTTPHeader] = []
    var chatIDHeaderName: String?
    var mcpAuthorizationScope: String?
    var persistsMCPAuthorizationScope = true
    var persistsServerConfiguration = true
    var mcpAuthorizationScopeWriteCount = 0
    var deleteAllCalled: Bool = false

    // MARK: - Public

    func getServerBaseURL() -> String {
        serverBaseURL
    }

    func setServerBaseURL(_ value: String) {
        serverBaseURL = value
    }

    func getAPIKey() -> String {
        apiKey
    }

    func setAPIKey(_ value: String) {
        apiKey = value
    }

    func getCustomHeaders() -> [ServerHTTPHeader] { customHeaders }
    func getChatIDHeaderName() -> String? { chatIDHeaderName }

    @discardableResult
    func setServerConfiguration(
        serverBaseURL: String, apiKey: String, customHeaders: [ServerHTTPHeader], chatIDHeaderName: String?
    ) -> Bool {
        guard persistsServerConfiguration else { return false }
        self.serverBaseURL = serverBaseURL
        self.apiKey = apiKey
        self.customHeaders = customHeaders
        self.chatIDHeaderName = chatIDHeaderName
        return true
    }

    func getMCPAuthorizationScope() -> String? {
        mcpAuthorizationScope
    }

    @discardableResult
    func setMCPAuthorizationScope(_ value: String) -> Bool {
        mcpAuthorizationScopeWriteCount += 1
        guard persistsMCPAuthorizationScope else { return false }
        mcpAuthorizationScope = value
        return true
    }

    func deleteAll() {
        serverBaseURL = ""
        apiKey = ""
        customHeaders = []
        chatIDHeaderName = nil
        mcpAuthorizationScope = nil
        mcpAuthorizationScopeWriteCount = 0
        deleteAllCalled = true
    }
}
