//
//  SettingsManagerModelCapabilitiesTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 03/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class SettingsManagerModelCapabilitiesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var sut: SettingsManager!
    private let suiteName = "com.artcc.openclient-llm.test.model-capabilities.\(UUID().uuidString)"
    private let server = "https://example.com/v1"

    override func setUp() async throws {
        try await super.setUp()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        sut = SettingsManager(defaults: defaults, keychainManager: MockKeychainManager())
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        sut = nil
        defaults = nil
        try await super.tearDown()
    }

    func test_override_restoredManager_preservesManualCapabilities() {
        sut.setModelCapabilityOverride([.vision, .functionCalling], for: "model", serverBaseURL: server)

        let restored = SettingsManager(defaults: defaults, keychainManager: MockKeychainManager())

        XCTAssertEqual(
            restored.getModelCapabilityOverride(for: "model", serverBaseURL: server), [.vision, .functionCalling]
        )
    }

    func test_override_emptySelection_remainsManualUntilReset() {
        XCTAssertNil(sut.getModelCapabilityOverride(for: "model", serverBaseURL: server))

        sut.setModelCapabilityOverride([], for: "model", serverBaseURL: server)
        XCTAssertEqual(sut.getModelCapabilityOverride(for: "model", serverBaseURL: server), [])

        sut.setModelCapabilityOverride(nil, for: "model", serverBaseURL: server)
        XCTAssertNil(sut.getModelCapabilityOverride(for: "model", serverBaseURL: server))
    }

    func test_override_equivalentServerURLs_sharePreferences() {
        sut.setModelCapabilityOverride([.vision], for: "model", serverBaseURL: " HTTPS://EXAMPLE.COM:443/v1/ ")

        XCTAssertEqual(sut.getModelCapabilityOverride(for: "model", serverBaseURL: server), [.vision])
    }

    func test_override_differentModelsHostsAndPaths_remainIsolated() {
        sut.setModelCapabilityOverride([.vision], for: "model", serverBaseURL: server)
        sut.setModelCapabilityOverride([.imageGeneration], for: "model", serverBaseURL: "https://other.example/v1")

        XCTAssertNil(sut.getModelCapabilityOverride(for: "other-model", serverBaseURL: server))
        XCTAssertNil(sut.getModelCapabilityOverride(for: "model", serverBaseURL: "https://example.com/other/v1"))
        XCTAssertEqual(sut.getModelCapabilityOverride(for: "model", serverBaseURL: server), [.vision])
        XCTAssertEqual(
            sut.getModelCapabilityOverride(for: "model", serverBaseURL: "https://other.example/v1"), [.imageGeneration]
        )
    }

    func test_deleteAll_removesOverridesForEveryServer() {
        sut.setModelCapabilityOverride([.vision], for: "model", serverBaseURL: server)
        sut.setModelCapabilityOverride([], for: "model", serverBaseURL: "https://other.example/v1")

        sut.deleteAll()

        XCTAssertNil(sut.getModelCapabilityOverride(for: "model", serverBaseURL: server))
        XCTAssertNil(sut.getModelCapabilityOverride(for: "model", serverBaseURL: "https://other.example/v1"))
    }
}
