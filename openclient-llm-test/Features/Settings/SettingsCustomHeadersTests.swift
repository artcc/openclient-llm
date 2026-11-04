//
//  SettingsCustomHeadersTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 02/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class SettingsCustomHeadersTests: XCTestCase {
    func test_send_cancelAdvancedSettings_discardsOnlyModalChanges() throws {
        let original = ServerHTTPHeader(name: "X-Test", value: "original")
        let sut = makeViewModel(headers: [original])
        sut.send(.advancedServerSettingsOpened)
        var edited = original
        edited.value = "edited"
        sut.send(.customHeaderChanged(edited))
        sut.send(.advancedServerSettingsCancelled)
        let state = try loadedState(sut)
        XCTAssertEqual(state.customHeaders, [original])
        XCTAssertNil(state.customHeaderDraft)
        sut.send(.advancedServerSettingsOpened)
        XCTAssertEqual(try loadedState(sut).customHeaderDraft, [original])
    }

    func test_send_doneThenSave_persistsHeadersTogetherWithServerConfiguration() throws {
        let save = MockSaveServerConfigurationUseCase()
        let sut = makeViewModel(save: save)
        sut.send(.advancedServerSettingsOpened)
        sut.send(.customHeaderAdded)
        var header = try XCTUnwrap(try loadedState(sut).customHeaderDraft?.first)
        header.name = "x-opencode-session"
        header.value = "test-session"
        sut.send(.customHeaderChanged(header))
        sut.send(.advancedServerSettingsApplied)
        XCTAssertEqual(try loadedState(sut).customHeaders, [header])
        XCTAssertFalse(try loadedState(sut).isSaved)
        XCTAssertNil(save.savedCustomHeaders)

        sut.send(.saveTapped)
        XCTAssertEqual(save.savedServerURL, "https://example.invalid")
        XCTAssertEqual(save.savedAPIKey, "test-key")
        XCTAssertEqual(save.savedCustomHeaders, [header])
        XCTAssertTrue(try loadedState(sut).isSaved)
    }

    func test_send_equivalentHeaderEdits_preservesDraftAndPassesItToSave() throws {
        let first = ServerHTTPHeader(name: "X-One", value: "one")
        let second = ServerHTTPHeader(name: "X-Two", value: "two")
        var renamed = first
        renamed.name = "x-one"
        let drafts = [[renamed, second], [second, first]]

        for draft in drafts {
            let save = MockSaveServerConfigurationUseCase()
            let sut = makeViewModel(headers: [first, second], save: save)
            sut.send(.saveTapped)
            XCTAssertTrue(try loadedState(sut).isSaved)
            sut.send(.advancedServerSettingsOpened)
            sut.send(.customHeaderRemoved(first.id))
            sut.send(.customHeaderRemoved(second.id))
            var expected: [ServerHTTPHeader] = []
            for header in draft {
                sut.send(.customHeaderAdded)
                var added = try XCTUnwrap(try loadedState(sut).customHeaderDraft?.last)
                added.name = header.name
                added.value = header.value
                sut.send(.customHeaderChanged(added))
                expected.append(added)
            }

            sut.send(.advancedServerSettingsApplied)

            XCTAssertEqual(try loadedState(sut).customHeaders, expected)
            XCTAssertNil(try loadedState(sut).customHeaderDraft)
            XCTAssertFalse(try loadedState(sut).isSaved)
            sut.send(.saveTapped)
            XCTAssertEqual(save.savedCustomHeaders, expected)
        }
    }

    func test_send_invalidHeader_keepsModalDraftAndOriginalConfiguration() throws {
        let original = ServerHTTPHeader(name: "X-Test", value: "original")
        let sut = makeViewModel(headers: [original])
        sut.send(.advancedServerSettingsOpened)
        var invalid = original
        invalid.name = "Authorization"
        sut.send(.customHeaderChanged(invalid))
        sut.send(.advancedServerSettingsApplied)
        XCTAssertEqual(try loadedState(sut).customHeaders, [original])
        XCTAssertEqual(try loadedState(sut).customHeaderDraft, [invalid])
    }

    func test_send_removeHeaderAndApply_clearsServerDraft() throws {
        let header = ServerHTTPHeader(name: "X-Test", value: "original")
        let sut = makeViewModel(headers: [header])
        sut.send(.advancedServerSettingsOpened)
        sut.send(.customHeaderRemoved(header.id))
        sut.send(.advancedServerSettingsApplied)
        XCTAssertEqual(try loadedState(sut).customHeaders, [])
        XCTAssertNil(try loadedState(sut).customHeaderDraft)
    }

    func test_send_saveFailure_preservesHeadersForRetry() throws {
        let save = MockSaveServerConfigurationUseCase()
        save.result = false
        let headers = [ServerHTTPHeader(name: "X-Test", value: "test")]
        let sut = makeViewModel(headers: headers, save: save)
        sut.send(.saveTapped)
        XCTAssertEqual(try loadedState(sut).customHeaders, headers)
        XCTAssertFalse(try loadedState(sut).isSaved)
        XCTAssertNotNil(try loadedState(sut).serverPersistenceError)
        save.result = true
        sut.send(.saveTapped)
        XCTAssertEqual(save.savedCustomHeaders, headers)
        XCTAssertTrue(try loadedState(sut).isSaved)
        XCTAssertNil(try loadedState(sut).serverPersistenceError)
    }

    func test_send_testConnection_usesUnsavedHeaders() async throws {
        let connection = MockTestServerConnectionUseCase()
        let headers = [ServerHTTPHeader(name: "X-Test", value: "unsaved")]
        let sut = makeViewModel(headers: headers, connection: connection)
        sut.send(.testConnectionTapped)
        await sut.serverConnectionTask?.value
        XCTAssertEqual(connection.testedCustomHeaders, headers)
        XCTAssertEqual(try loadedState(sut).connectionStatus, .success)
    }

    func test_send_headersChangedDuringConnectionTest_ignoresStaleCompletion() async throws {
        let connection = MockTestServerConnectionUseCase()
        let header = ServerHTTPHeader(name: "X-Test", value: "before")
        let sut = makeViewModel(headers: [header], connection: connection)
        connection.onExecute = {
            sut.send(.advancedServerSettingsOpened)
            var edited = header
            edited.value = "after"
            sut.send(.customHeaderChanged(edited))
            sut.send(.advancedServerSettingsApplied)
        }
        defer { connection.onExecute = nil }
        sut.send(.testConnectionTapped)
        await sut.serverConnectionTask?.value
        XCTAssertEqual(try loadedState(sut).connectionStatus, .idle)
        XCTAssertEqual(try loadedState(sut).customHeaders.first?.value, "after")
    }

    private func loadedState(_ sut: SettingsViewModel) throws -> SettingsViewModel.LoadedState {
        guard case .loaded(let state) = sut.state else { throw APIError.invalidResponse }
        return state
    }

    func test_send_automaticHeaderCancelAndDone_preservesTwoStageSave() throws {
        let save = MockSaveServerConfigurationUseCase()
        let sut = makeViewModel(save: save)
        XCTAssertNil(try loadedState(sut).chatIDHeaderName)
        sut.send(.advancedServerSettingsOpened)
        sut.send(.chatIDHeaderToggled(true))
        sut.send(.chatIDHeaderNameChanged("X-Chat-ID"))
        sut.send(.advancedServerSettingsCancelled)
        XCTAssertNil(try loadedState(sut).chatIDHeaderName)
        sut.send(.advancedServerSettingsOpened)
        XCTAssertNil(try loadedState(sut).chatIDHeaderNameDraft)

        sut.send(.chatIDHeaderToggled(true))
        sut.send(.chatIDHeaderNameChanged("X-Chat-ID"))
        sut.send(.advancedServerSettingsApplied)
        XCTAssertEqual(try loadedState(sut).chatIDHeaderName, "X-Chat-ID")
        XCTAssertFalse(try loadedState(sut).isSaved)
        XCTAssertNil(save.savedChatIDHeaderName)
        save.result = false
        sut.send(.saveTapped)
        XCTAssertEqual(try loadedState(sut).chatIDHeaderName, "X-Chat-ID")
        XCTAssertNotNil(try loadedState(sut).serverPersistenceError)
        save.result = true
        sut.send(.saveTapped)
        XCTAssertEqual(save.savedChatIDHeaderName, "X-Chat-ID")
        XCTAssertTrue(try loadedState(sut).isSaved)

        sut.send(.advancedServerSettingsOpened)
        sut.send(.chatIDHeaderToggled(false))
        sut.send(.advancedServerSettingsApplied)
        sut.send(.saveTapped)
        XCTAssertNil(save.savedChatIDHeaderName)
        XCTAssertNil(try loadedState(sut).chatIDHeaderName)
    }

    func test_send_invalidAutomaticHeader_keepsModalOpenAndStaticHeadersIntact() throws {
        let header = ServerHTTPHeader(name: "X-Chat-ID", value: "static")
        let sut = makeViewModel(headers: [header])
        sut.send(.advancedServerSettingsOpened)
        sut.send(.chatIDHeaderToggled(true))
        for invalidName in ["", "Authorization", "x-chat-id"] {
            sut.send(.chatIDHeaderNameChanged(invalidName))
            sut.send(.advancedServerSettingsApplied)
            XCTAssertEqual(try loadedState(sut).chatIDHeaderNameDraft, invalidName)
            XCTAssertEqual(try loadedState(sut).customHeaderDraft, [header])
            XCTAssertNil(try loadedState(sut).chatIDHeaderName)
        }
        sut.send(.chatIDHeaderNameChanged("X-Conversation-ID"))
        sut.send(.advancedServerSettingsApplied)
        XCTAssertEqual(try loadedState(sut).chatIDHeaderName, "X-Conversation-ID")
        XCTAssertEqual(try loadedState(sut).customHeaders, [header])
        XCTAssertNil(try loadedState(sut).customHeaderDraft)
    }

    func test_send_automaticHeaderChangedDuringConnectionTest_ignoresStaleCompletion() async throws {
        let connection = MockTestServerConnectionUseCase()
        let sut = makeViewModel(connection: connection)
        connection.onExecute = {
            sut.send(.advancedServerSettingsOpened)
            sut.send(.chatIDHeaderToggled(true))
            sut.send(.chatIDHeaderNameChanged("X-Chat-ID"))
            sut.send(.advancedServerSettingsApplied)
        }
        defer { connection.onExecute = nil }
        sut.send(.testConnectionTapped)
        await sut.serverConnectionTask?.value
        XCTAssertEqual(try loadedState(sut).connectionStatus, .idle)
        XCTAssertEqual(try loadedState(sut).chatIDHeaderName, "X-Chat-ID")
        XCTAssertEqual(connection.testedCustomHeaders, [])
    }

    private func makeViewModel(
        headers: [ServerHTTPHeader] = [],
        save: MockSaveServerConfigurationUseCase = MockSaveServerConfigurationUseCase(),
        connection: MockTestServerConnectionUseCase = MockTestServerConnectionUseCase()
    ) -> SettingsViewModel {
        SettingsViewModel(
            state: .loaded(.init(serverURL: "https://example.invalid", apiKey: "test-key", customHeaders: headers)),
            saveServerConfigurationUseCase: save,
            testServerConnectionUseCase: connection,
            checkLiteLLMHealthUseCase: MockCheckLiteLLMHealthUseCase(),
            fetchSearchToolsUseCase: MockFetchSearchToolsUseCase(),
            fetchMCPToolsUseCase: MockFetchMCPToolsUseCase(),
            settingsManager: MockSettingsManager(),
            cloudSyncManager: MockCloudSyncManager(),
            synchronizeAppDataUseCase: MockSynchronizeAppDataUseCase(),
            cloudSyncCoordinator: MockEnableCloudSyncUseCase(),
            userProfileManager: MockUserProfileManager(),
            cloudSyncRuntimeStore: CloudSyncRuntimeStore(),
            cloudAccountAssociation: MockCloudAccountAssociation(),
            resetAppUseCase: MockResetAppDataUseCase(),
            appIconManager: MockAppIconManager(),
            remoteConfigManager: MockRemoteConfigManager()
        )
    }
}
