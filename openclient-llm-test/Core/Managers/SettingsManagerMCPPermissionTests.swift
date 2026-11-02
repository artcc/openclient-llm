//
//  SettingsManagerMCPPermissionTests.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 14/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class SettingsManagerMCPPermissionTests: XCTestCase {
    // MARK: - Properties

    private var sut: SettingsManager!
    private var defaults: UserDefaults!
    private var keychain: MockKeychainManager!
    private let suiteName = "com.artcc.openclient-llm.test.mcp-permissions"

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        keychain = MockKeychainManager()
        sut = SettingsManager(defaults: defaults, keychainManager: keychain)
    }

    override func tearDown() async throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        sut = nil
        defaults = nil
        keychain = nil
        try await super.tearDown()
    }

    // MARK: - Tests

    func test_getMCPToolPermission_withoutStoredValue_returnsAsk() {
        // Given
        let permissionKey = "tool-key"

        // When
        let permission = sut.getMCPToolPermission(for: permissionKey)

        // Then
        XCTAssertEqual(permission, .ask)
    }

    func test_setMCPToolPermission_allPolicies_roundTripsIndependently() {
        // Given
        let allowKey = "allow"
        let askKey = "ask"
        let denyKey = "deny"

        // When
        sut.setMCPToolPermission(.alwaysAllow, for: allowKey)
        sut.setMCPToolPermission(.ask, for: askKey)
        sut.setMCPToolPermission(.deny, for: denyKey)

        // Then
        XCTAssertEqual(sut.getMCPToolPermission(for: allowKey), .alwaysAllow)
        XCTAssertEqual(sut.getMCPToolPermission(for: askKey), .ask)
        XCTAssertEqual(sut.getMCPToolPermission(for: denyKey), .deny)
    }

    func test_setMCPToolPermission_multipleKeys_updatesEveryPermission() {
        // Given
        let permissionKeys = ["first", "second", "first"]

        // When
        sut.setMCPToolPermission(.alwaysAllow, for: permissionKeys)

        // Then
        XCTAssertEqual(sut.getMCPToolPermission(for: "first"), .alwaysAllow)
        XCTAssertEqual(sut.getMCPToolPermission(for: "second"), .alwaysAllow)
    }

    func test_setMCPToolPermission_fromDifferentManagers_preservesIndependentValues() {
        // Given
        let second = SettingsManager(defaults: defaults, keychainManager: MockKeychainManager())

        // When
        sut.setMCPToolPermission(.alwaysAllow, for: "first")
        second.setMCPToolPermission(.deny, for: "second")

        // Then
        XCTAssertEqual(sut.getMCPToolPermission(for: "first"), .alwaysAllow)
        XCTAssertEqual(sut.getMCPToolPermission(for: "second"), .deny)
    }

    func test_getMCPToolPermission_withUnknownRawValue_failsClosedToAsk() {
        // Given
        defaults.set("future-value", forKey: "mcpToolPermission.tool-key")

        // When
        let permission = sut.getMCPToolPermission(for: "tool-key")

        // Then
        XCTAssertEqual(permission, .ask)
    }

    func test_deleteAll_withStoredMCPPermission_clearsPermission() {
        // Given
        sut.setMCPToolPermission(.alwaysAllow, for: "tool-key")

        // When
        sut.deleteAll()

        // Then
        XCTAssertEqual(sut.getMCPToolPermission(for: "tool-key"), .ask)
    }

    func test_setMCPToolConfigurationKey_validValue_roundTrips() {
        // Given
        let toolId = "github-create"

        // When
        sut.setMCPToolConfigurationKey("configuration-key", for: toolId)

        // Then
        XCTAssertEqual(sut.getMCPToolConfigurationKey(for: toolId), "configuration-key")
    }

    func test_deleteAll_withStoredMCPConfiguration_clearsConfiguration() {
        // Given
        let toolId = "github-create"
        sut.setMCPToolConfigurationKey("configuration-key", for: toolId)

        // When
        sut.deleteAll()

        // Then
        XCTAssertNil(sut.getMCPToolConfigurationKey(for: toolId))
    }

    func test_getMCPAuthorizationScope_reusesScopeUntilCredentialsChange() {
        // Given
        let original = sut.getMCPAuthorizationScope()

        // When
        let repeated = sut.getMCPAuthorizationScope()
        sut.setAPIKey("new-key")
        let rotated = sut.getMCPAuthorizationScope()

        // Then
        XCTAssertEqual(repeated, original)
        XCTAssertNotEqual(rotated, original)
    }

    func test_getMCPAuthorizationScope_scopeWriteFails_returnsUnavailableScope() {
        // Given
        keychain.persistsMCPAuthorizationScope = false

        // When
        let scope = sut.getMCPAuthorizationScope()

        // Then
        XCTAssertTrue(scope.isEmpty)
    }

    func test_setServerConfiguration_equivalentNormalizedEndpoint_preservesAuthorizationScope() {
        // Given
        sut.setServerConfiguration(serverBaseURL: "https://EXAMPLE.com:443/", apiKey: "key")
        let originalScope = sut.getMCPAuthorizationScope()

        // When
        sut.setServerConfiguration(serverBaseURL: "https://example.com", apiKey: "key")

        // Then
        XCTAssertEqual(sut.getMCPAuthorizationScope(), originalScope)
        XCTAssertEqual(sut.getServerBaseURL(), "https://example.com")
    }

    func test_setServerConfiguration_scopeWriteFails_preservesPreviousCredentials() {
        // Given
        keychain.serverBaseURL = "https://old.example.com"
        keychain.apiKey = "old-key"
        keychain.mcpAuthorizationScope = "old-scope"
        keychain.persistsMCPAuthorizationScope = false

        // When
        let didSave = sut.setServerConfiguration(
            serverBaseURL: "https://new.example.com",
            apiKey: "new-key"
        )

        // Then
        XCTAssertFalse(didSave)
        XCTAssertEqual(sut.getServerBaseURL(), "https://old.example.com")
        XCTAssertEqual(sut.getAPIKey(), "old-key")
        XCTAssertEqual(sut.getMCPAuthorizationScope(), "old-scope")
    }

    func test_setServerConfiguration_configurationWriteFails_preservesCredentialPair() {
        // Given
        keychain.serverBaseURL = "https://old.example.com"
        keychain.apiKey = "old-key"
        keychain.mcpAuthorizationScope = "old-scope"
        keychain.persistsServerConfiguration = false

        // When
        let didSave = sut.setServerConfiguration(
            serverBaseURL: "https://new.example.com",
            apiKey: "new-key"
        )

        // Then
        XCTAssertFalse(didSave)
        XCTAssertEqual(sut.getServerBaseURL(), "https://old.example.com")
        XCTAssertEqual(sut.getAPIKey(), "old-key")
        XCTAssertNotEqual(sut.getMCPAuthorizationScope(), "old-scope")
    }

    func test_setServerConfiguration_headersChanged_invalidatesPreviousAuthorization() {
        // Given
        sut.setServerConfiguration(serverBaseURL: "https://example.invalid", apiKey: "key")
        sut.setMCPToolConfigurationKey("old-tool-key", for: "tool")
        let originalScope = sut.getMCPAuthorizationScope()
        let headers = [ServerHTTPHeader(name: "X-Token", value: "new-token")]

        // When
        let saved = sut.setServerConfiguration(
            serverBaseURL: "https://example.invalid", apiKey: "key", customHeaders: headers
        )

        // Then
        XCTAssertTrue(saved)
        XCTAssertNotEqual(sut.getMCPAuthorizationScope(), originalScope)
        XCTAssertNil(sut.getMCPToolConfigurationKey(for: "tool"))
        XCTAssertEqual(sut.getCustomHeaders(), headers)
        let newScope = sut.getMCPAuthorizationScope()
        sut.setServerConfiguration(
            serverBaseURL: "https://example.invalid", apiKey: "key",
            customHeaders: [.init(name: "x-token", value: "new-token")]
        )
        XCTAssertEqual(sut.getMCPAuthorizationScope(), newScope)
    }

    func test_setServerConfiguration_equivalentHeaderEdits_persistsWithoutInvalidatingAuthorization() {
        let first = ServerHTTPHeader(name: "X-One", value: "one")
        let second = ServerHTTPHeader(name: "X-Two", value: "two")
        var renamed = first
        renamed.name = "x-one"
        let drafts = [[renamed, second], [second, first]]

        for draft in drafts {
            XCTAssertTrue(sut.setServerConfiguration(
                serverBaseURL: "https://example.invalid", apiKey: "key", customHeaders: [first, second]
            ))
            sut.setMCPToolConfigurationKey("tool-key", for: "tool")
            sut.setMCPToolPermission(.alwaysAllow, for: "tool-key")
            let scope = sut.getMCPAuthorizationScope()

            let saved = sut.setServerConfiguration(
                serverBaseURL: "https://example.invalid", apiKey: "key", customHeaders: draft
            )

            XCTAssertTrue(saved)
            XCTAssertEqual(sut.getCustomHeaders(), draft)
            XCTAssertEqual(sut.getMCPAuthorizationScope(), scope)
            XCTAssertEqual(sut.getMCPToolConfigurationKey(for: "tool"), "tool-key")
            XCTAssertEqual(sut.getMCPToolPermission(for: "tool-key"), .alwaysAllow)
        }
    }

    func test_setServerConfiguration_equivalentHeaderWriteFails_reportsFailureWithoutChangingAuthorization() {
        let original = ServerHTTPHeader(name: "X-Token", value: "token")
        XCTAssertTrue(sut.setServerConfiguration(
            serverBaseURL: "https://example.invalid", apiKey: "key", customHeaders: [original]
        ))
        let scope = sut.getMCPAuthorizationScope()
        keychain.persistsServerConfiguration = false
        var renamed = original
        renamed.name = "x-token"

        let saved = sut.setServerConfiguration(
            serverBaseURL: "https://example.invalid", apiKey: "key", customHeaders: [renamed]
        )

        XCTAssertFalse(saved)
        XCTAssertEqual(sut.getCustomHeaders(), [original])
        XCTAssertEqual(sut.getMCPAuthorizationScope(), scope)
    }

    func test_setServerConfiguration_failedHeaderWrite_preservesPreviousHeaderValues() {
        let previous = [ServerHTTPHeader(name: "X-Token", value: "old-token")]
        keychain.customHeaders = previous
        keychain.persistsServerConfiguration = false
        let saved = sut.setServerConfiguration(
            serverBaseURL: "https://example.invalid", apiKey: "new-key",
            customHeaders: [.init(name: "X-Token", value: "new-token")]
        )
        XCTAssertFalse(saved)
        XCTAssertEqual(sut.getCustomHeaders(), previous)
    }

    func test_publishMCPToolDiscovery_olderCompletionDoesNotReplaceNewerCompletion() {
        // Given
        let toolId = MCPToolInfo.identifier(serverId: "server", name: "tool")
        let servers = [MCPServerInfo(
            serverId: "server",
            serverName: "Server",
            description: nil,
            allowedTools: nil
        )]
        let olderRevision = sut.beginMCPToolDiscovery()
        let newerRevision = sut.beginMCPToolDiscovery()

        // When
        let publishedNewer = sut.publishMCPToolDiscovery(
            revision: newerRevision,
            configurationKeys: [toolId: "newer-key"],
            enabledToolIds: [toolId],
            servers: servers,
            failedServerIds: []
        )
        let publishedOlder = sut.publishMCPToolDiscovery(
            revision: olderRevision,
            configurationKeys: [toolId: "older-key"],
            enabledToolIds: [],
            servers: servers,
            failedServerIds: []
        )

        // Then
        XCTAssertTrue(publishedNewer)
        XCTAssertFalse(publishedOlder)
        XCTAssertEqual(sut.getMCPToolConfigurationKey(for: toolId), "newer-key")
        XCTAssertEqual(sut.getEnabledMCPToolIds(), [toolId])
    }

    func test_publishMCPToolDiscoveryFailure_newerFailureRejectsOlderSuccess() {
        // Given
        let olderRevision = sut.beginMCPToolDiscovery()
        let newerRevision = sut.beginMCPToolDiscovery()

        // When
        let publishedFailure = sut.publishMCPToolDiscoveryFailure(revision: newerRevision)
        let publishedOlder = sut.publishMCPToolDiscovery(
            revision: olderRevision,
            configurationKeys: ["tool": "stale-key"],
            enabledToolIds: ["tool"],
            servers: [makeServer(allowedTools: nil)],
            failedServerIds: []
        )

        // Then
        XCTAssertTrue(publishedFailure)
        XCTAssertFalse(publishedOlder)
        XCTAssertNil(sut.getMCPToolConfigurationKey(for: "tool"))
        XCTAssertTrue(sut.getIsMCPDiscoveryFailed())
    }

    func test_publishMCPToolDiscovery_failedServer_preservesNewerPublishedConfiguration() {
        // Given
        let toolId = MCPToolInfo.identifier(serverId: "server", name: "tool")
        let servers = [makeServer(allowedTools: nil)]
        _ = sut.publishMCPToolDiscovery(
            revision: sut.beginMCPToolDiscovery(),
            configurationKeys: [toolId: "current-key"],
            enabledToolIds: [toolId],
            servers: servers,
            failedServerIds: []
        )

        // When
        _ = sut.publishMCPToolDiscovery(
            revision: sut.beginMCPToolDiscovery(),
            configurationKeys: [:],
            enabledToolIds: [],
            servers: servers,
            failedServerIds: ["server"]
        )

        // Then
        XCTAssertEqual(sut.getMCPToolConfigurationKey(for: toolId), "current-key")
        XCTAssertEqual(sut.getEnabledMCPToolIds(), [toolId])
        XCTAssertEqual(sut.getFailedMCPServerIds(), ["server"])
    }

    func test_publishMCPToolDiscovery_failedServerDisallowsTool_removesPublishedConfiguration() {
        // Given
        let toolId = MCPToolInfo.identifier(serverId: "server", name: "tool")
        _ = sut.publishMCPToolDiscovery(
            revision: sut.beginMCPToolDiscovery(),
            configurationKeys: [toolId: "current-key"],
            enabledToolIds: [toolId],
            servers: [makeServer(allowedTools: nil)],
            failedServerIds: []
        )

        // When
        _ = sut.publishMCPToolDiscovery(
            revision: sut.beginMCPToolDiscovery(),
            configurationKeys: [:],
            enabledToolIds: [],
            servers: [makeServer(allowedTools: [])],
            failedServerIds: ["server"]
        )

        // Then
        XCTAssertNil(sut.getMCPToolConfigurationKey(for: toolId))
        XCTAssertTrue(sut.getEnabledMCPToolIds().isEmpty)
    }

    func test_replaceMCPToolConfigurationKeys_removedTool_clearsStaleConfiguration() {
        // Given
        sut.replaceMCPToolConfigurationKeys(["first": "first-key", "removed": "removed-key"])

        // When
        sut.replaceMCPToolConfigurationKeys(["first": "updated-key"])

        // Then
        XCTAssertEqual(sut.getMCPToolConfigurationKey(for: "first"), "updated-key")
        XCTAssertNil(sut.getMCPToolConfigurationKey(for: "removed"))
    }
}

private extension SettingsManagerMCPPermissionTests {
    func makeServer(allowedTools: [String]?) -> MCPServerInfo {
        MCPServerInfo(
            serverId: "server",
            serverName: "Server",
            description: nil,
            allowedTools: allowedTools
        )
    }
}
