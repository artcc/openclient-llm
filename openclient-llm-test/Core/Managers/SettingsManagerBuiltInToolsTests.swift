//
//  SettingsManagerBuiltInToolsTests.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 11/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class SettingsManagerBuiltInToolsTests: XCTestCase {
    private var sut: SettingsManager!
    private var defaults: UserDefaults!
    private let suiteName = "com.artcc.openclient-llm.test.built-in-tools.\(UUID().uuidString)"

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

    func test_getIsBuiltInToolEnabled_noPreferences_enablesEveryBuiltInTool() {
        // Given
        let tools = BuiltInTool.allCases

        // When
        let enabled = tools.filter { sut.getIsBuiltInToolEnabled($0) }

        // Then
        XCTAssertEqual(enabled, tools)
    }

    func test_setIsBuiltInToolEnabled_disabledTool_persistsWithoutChangingOtherSettings() {
        // Given
        sut.setEnabledMCPToolIds(["server-tool"])
        sut.setIsWebSearchEnabled(true)
        sut.setSelectedVisionModelId("vision")

        // When
        sut.setIsBuiltInToolEnabled(false, for: .webSearch)
        let restored = SettingsManager(defaults: defaults, keychainManager: MockKeychainManager())

        // Then
        XCTAssertFalse(restored.getIsBuiltInToolEnabled(.webSearch))
        XCTAssertTrue(restored.getIsBuiltInToolEnabled(.saveMemory))
        XCTAssertTrue(restored.getIsWebSearchEnabled())
        XCTAssertEqual(restored.getEnabledMCPToolIds(), ["server-tool"])
        XCTAssertEqual(restored.getSelectedVisionModelId(), "vision")
    }

    func test_deleteAll_disabledBuiltInTools_restoresDefaults() {
        // Given
        for tool in BuiltInTool.allCases {
            sut.setIsBuiltInToolEnabled(false, for: tool)
        }

        // When
        sut.deleteAll()
        let restored = SettingsManager(defaults: defaults, keychainManager: MockKeychainManager())

        // Then
        XCTAssertTrue(BuiltInTool.allCases.allSatisfy { restored.getIsBuiltInToolEnabled($0) })
    }
}
