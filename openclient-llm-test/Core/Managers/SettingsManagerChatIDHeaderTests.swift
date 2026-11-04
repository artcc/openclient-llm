//
//  SettingsManagerChatIDHeaderTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 04/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class SettingsManagerChatIDHeaderTests: XCTestCase {
    func test_setServerConfiguration_automaticHeaderChanges_rotateAuthorizationExceptForCapitalization() throws {
        let suite = "com.openclient-llm.tests.chat-header.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = MockKeychainManager()
        let sut = SettingsManager(defaults: defaults, keychainManager: keychain)
        XCTAssertTrue(sut.setServerConfiguration(serverBaseURL: "https://example.invalid", apiKey: "key"))

        let names: [String?] = ["X-Chat-ID", "x-chat-id", "X-Conversation-ID", nil]
        for name in names {
            let previousScope = sut.getMCPAuthorizationScope()
            sut.setMCPToolConfigurationKey("tool-key", for: "tool")
            XCTAssertTrue(sut.setServerConfiguration(
                serverBaseURL: "https://example.invalid", apiKey: "key", customHeaders: [], chatIDHeaderName: name
            ))
            XCTAssertEqual(sut.getChatIDHeaderName(), name)
            if name == "x-chat-id" {
                XCTAssertEqual(sut.getMCPAuthorizationScope(), previousScope)
                XCTAssertEqual(sut.getMCPToolConfigurationKey(for: "tool"), "tool-key")
            } else {
                XCTAssertNotEqual(sut.getMCPAuthorizationScope(), previousScope)
                XCTAssertNil(sut.getMCPToolConfigurationKey(for: "tool"))
            }
        }
    }

    func test_execute_legacyServerSave_preservesAutomaticHeaderAndAuthorization() throws {
        let suite = "com.openclient-llm.tests.chat-header.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = MockKeychainManager()
        let settings = SettingsManager(defaults: defaults, keychainManager: keychain)
        XCTAssertTrue(settings.setServerConfiguration(
            serverBaseURL: "https://example.invalid", apiKey: "key", customHeaders: [], chatIDHeaderName: "X-Chat-ID"
        ))
        let scope = settings.getMCPAuthorizationScope()
        let sut = SaveServerConfigurationUseCase(settingsManager: settings)

        XCTAssertTrue(sut.execute(serverURL: "https://example.invalid", apiKey: "key"))

        XCTAssertEqual(settings.getChatIDHeaderName(), "X-Chat-ID")
        XCTAssertEqual(settings.getMCPAuthorizationScope(), scope)
        keychain.persistsServerConfiguration = false
        XCTAssertFalse(sut.execute(
            serverURL: "https://example.invalid", apiKey: "key", customHeaders: [], chatIDHeaderName: nil
        ))
        XCTAssertEqual(settings.getChatIDHeaderName(), "X-Chat-ID")
    }
}
