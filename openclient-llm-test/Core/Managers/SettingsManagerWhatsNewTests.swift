//
//  SettingsManagerWhatsNewTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 24/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class SettingsManagerWhatsNewTests: XCTestCase {
    private let suiteName = "com.artcc.openclient-llm.test.whatsNew.\(UUID().uuidString)"

    override func tearDown() async throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    func test_whatsNewSettings_reopeningSuite_restoresSeenIDsAndFreshInstallVersion() throws {
        // Given
        let settings = try makeSettings()
        settings.seenWhatsNewIDs = ["chat-folders", "voice-input"]
        settings.freshInstallVersion = "2.0"

        // When
        let reopened = try makeSettings()

        // Then
        XCTAssertEqual(reopened.seenWhatsNewIDs, ["chat-folders", "voice-input"])
        XCTAssertEqual(reopened.freshInstallVersion, "2.0")
    }

    func test_deleteAll_withWhatsNewSettings_reopenedSuiteHasNoSeenIDsOrFreshInstallVersion() throws {
        // Given
        let settings = try makeSettings()
        settings.seenWhatsNewIDs = ["chat-folders"]
        settings.freshInstallVersion = "2.0"

        // When
        settings.deleteAll()

        // Then
        let reopened = try makeSettings()
        XCTAssertTrue(reopened.seenWhatsNewIDs.isEmpty)
        XCTAssertNil(reopened.freshInstallVersion)
    }

    private func makeSettings() throws -> SettingsManager {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        return SettingsManager(defaults: defaults, keychainManager: MockKeychainManager())
    }
}
