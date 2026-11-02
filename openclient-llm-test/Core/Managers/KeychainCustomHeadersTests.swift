//
//  KeychainCustomHeadersTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 02/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Security
import XCTest
@testable import openclient_llm

@MainActor
final class KeychainCustomHeadersTests: XCTestCase {
    func test_setServerConfiguration_roundTripAndLegacySetters_preserveHeaders() {
        let service = "com.openclient-llm.tests.headers.\(UUID().uuidString)"
        let sut = KeychainManager(service: service)
        defer { sut.deleteAll() }
        let headers = [ServerHTTPHeader(name: "X-Token", value: "synthetic-token")]
        XCTAssertTrue(sut.setServerConfiguration(
            serverBaseURL: "https://example.invalid", apiKey: "test-key", customHeaders: headers
        ))
        let reloaded = KeychainManager(service: service)
        XCTAssertEqual(reloaded.getCustomHeaders(), headers)
        sut.setAPIKey("replacement-key")
        sut.setServerBaseURL("https://example.invalid/v1")
        XCTAssertEqual(sut.getCustomHeaders(), headers)
        XCTAssertEqual(sut.getAPIKey(), "replacement-key")
        XCTAssertEqual(sut.getServerBaseURL(), "https://example.invalid/v1")
        sut.deleteAll()
        XCTAssertEqual(sut.getCustomHeaders(), [])
    }

    func test_getCustomHeaders_olderStoredConfiguration_preservesCredentialsAndUsesEmptyHeaders() {
        let service = "com.openclient-llm.tests.headers.\(UUID().uuidString)"
        let sut = KeychainManager(service: service)
        defer { sut.deleteAll() }
        let data = Data(#"{"serverBaseURL":"https://example.invalid","apiKey":"test-key"}"#.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "com.openclient-llm.serverConfiguration",
            kSecUseDataProtectionKeychain as String: true,
            kSecValueData as String: data
        ]
        XCTAssertEqual(SecItemAdd(query as CFDictionary, nil), errSecSuccess)
        XCTAssertEqual(sut.getServerBaseURL(), "https://example.invalid")
        XCTAssertEqual(sut.getAPIKey(), "test-key")
        XCTAssertEqual(sut.getCustomHeaders(), [])
    }

    func test_setServerConfiguration_invalidHeaders_preservesExistingConfiguration() {
        let sut = KeychainManager(service: "com.openclient-llm.tests.headers.\(UUID().uuidString)")
        defer { sut.deleteAll() }
        XCTAssertTrue(sut.setServerConfiguration(serverBaseURL: "https://example.invalid", apiKey: "old-key"))
        XCTAssertFalse(sut.setServerConfiguration(
            serverBaseURL: "https://other.invalid", apiKey: "new-key",
            customHeaders: [.init(name: "Invalid Name", value: "test")]
        ))
        XCTAssertEqual(sut.getServerBaseURL(), "https://example.invalid")
        XCTAssertEqual(sut.getAPIKey(), "old-key")
        XCTAssertEqual(sut.getCustomHeaders(), [])
    }
}
