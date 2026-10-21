//
//  SettingsManagerModelConfigurationTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 21/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class SettingsManagerModelConfigurationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var sut: SettingsManager!
    private let suiteName = "com.artcc.openclient-llm.test.model-configuration.\(UUID().uuidString)"

    override func setUp() async throws {
        try await super.setUp()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        sut = SettingsManager(defaults: defaults, keychainManager: MockKeychainManager())
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        sut = nil
        try await super.tearDown()
    }

    func test_getConfiguration_noSavedDefaults_returnsUnconfiguredBlock() {
        XCTAssertEqual(sut.getGlobalChatModelConfiguration(), .default)
    }

    func test_setConfiguration_restoredManager_preservesCompleteBlockIncludingZero() {
        let configuration = ChatModelConfiguration(
            parameters: ModelParameters(temperature: 0, maxTokens: 4096, topP: 0), contextWindowTokens: 8192
        )

        sut.setGlobalChatModelConfiguration(configuration)
        let restored = SettingsManager(defaults: defaults, keychainManager: MockKeychainManager())

        XCTAssertEqual(restored.getGlobalChatModelConfiguration(), configuration)
    }

    func test_setConfiguration_reset_removesAllCustomValues() {
        sut.setGlobalChatModelConfiguration(ChatModelConfiguration(parameters: ModelParameters(maxTokens: 2048)))

        sut.setGlobalChatModelConfiguration(.default)

        XCTAssertEqual(sut.getGlobalChatModelConfiguration(), .default)
    }

    func test_deleteAll_removesGlobalConfiguration() {
        sut.setGlobalChatModelConfiguration(ChatModelConfiguration(contextWindowTokens: 8192))

        sut.deleteAll()

        XCTAssertEqual(sut.getGlobalChatModelConfiguration(), .default)
    }

    func test_setConfiguration_notifiesOpenChats() async {
        let changed = expectation(forNotification: .chatModelConfigurationDidChange, object: nil)

        sut.setGlobalChatModelConfiguration(ChatModelConfiguration(contextWindowTokens: 8192))

        await fulfillment(of: [changed], timeout: 2)
    }
}
