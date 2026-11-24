//
//  LaunchViewModelTests.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class LaunchViewModelTests: XCTestCase {
    // MARK: - Properties

    private var sut: LaunchViewModel!
    private var mockUseCase: MockCheckOnboardingUseCase!
    private var mockResetAppData: MockResetAppDataUseCase!
    private var mockAttachmentMigration: MockAttachmentMigrationUseCase!
    private var mockRemoteConfigManager: MockRemoteConfigManager!

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()

        mockUseCase = MockCheckOnboardingUseCase()
        mockResetAppData = MockResetAppDataUseCase()
        mockAttachmentMigration = MockAttachmentMigrationUseCase()
        mockRemoteConfigManager = MockRemoteConfigManager()
        sut = LaunchViewModel(
            checkOnboardingUseCase: mockUseCase,
            resetAppDataUseCase: mockResetAppData,
            configureVoticeUseCase: NoOpConfigureVoticeUseCase(),
            attachmentMigrationUseCase: mockAttachmentMigration,
            remoteConfigManager: mockRemoteConfigManager,
            settingsManager: MockSettingsManager(),
            announcementSession: LaunchAnnouncementSession(),
            currentVersion: "1.0.0",
            launchDelay: .zero
        )
    }

    override func tearDown() async throws {
        sut = nil
        mockUseCase = nil
        mockResetAppData = nil
        mockAttachmentMigration = nil
        mockRemoteConfigManager = nil

        try await super.tearDown()
    }

    // MARK: - Tests

    func test_init_defaultState_isLoading() {
        // Then
        XCTAssertEqual(sut.state, .loading)
    }

    func test_send_viewAppeared_onboardingNotCompleted_setsOnboardingState() async {
        // Given
        mockUseCase.result = false

        // When
        sut.send(.viewAppeared)
        await waitForLaunch()

        // Then
        XCTAssertEqual(sut.state, .onboarding)
    }

    func test_send_viewAppeared_onboardingNotCompleted_resetsAppData() async {
        // Given
        mockUseCase.result = false

        // When
        sut.send(.viewAppeared)
        await waitForLaunch()

        // Then
        XCTAssertTrue(mockResetAppData.executeCalled)
    }

    func test_send_viewDisappearedBeforeResetStarts_finishesCleanupWhileClosedAndReusesItOnReopen() async throws {
        mockUseCase.result = false
        let resetFinished = expectation(description: "Initial cleanup finished while the window was closed")
        mockResetAppData.onExecute = {
            try Task.checkCancellation()
            resetFinished.fulfill()
        }

        sut.send(.viewAppeared)
        let firstLaunch = try XCTUnwrap(sut.launchTask)
        sut.send(.viewDisappeared)

        await fulfillment(of: [resetFinished], timeout: 2)
        await firstLaunch.value
        XCTAssertEqual(sut.state, .loading)
        sut.send(.viewAppeared)
        await waitForLaunch()
        XCTAssertEqual(mockResetAppData.executeCallCount, 1)
        XCTAssertEqual(sut.state, .onboarding)
    }

    func test_send_reopenDuringInitialReset_completesTheSameCleanupWithoutCancellation() async {
        mockUseCase.result = false
        let resetStarted = expectation(description: "Initial cleanup reached its checkpoint")
        let gate = TestAsyncGate()
        var cleanupFinished = false
        mockResetAppData.onExecute = {
            resetStarted.fulfill()
            await gate.wait()
            try Task.checkCancellation()
            cleanupFinished = true
        }
        sut.send(.viewAppeared)
        let firstLaunch = sut.launchTask
        await fulfillment(of: [resetStarted], timeout: 2)

        sut.send(.viewDisappeared)
        sut.send(.viewAppeared)
        await gate.open()

        await firstLaunch?.value
        await waitForLaunch()
        XCTAssertTrue(cleanupFinished)
        XCTAssertEqual(mockResetAppData.executeCallCount, 1)
        XCTAssertEqual(sut.state, .onboarding)
    }

    func test_send_viewAppeared_initialResetFails_setsResetFailedState() async {
        // Given
        mockUseCase.result = false
        mockResetAppData.executeError = NSError(domain: "LaunchViewModelTests", code: 1)

        // When
        sut.send(.viewAppeared)
        await waitForLaunch()

        // Then
        XCTAssertEqual(sut.state, .resetFailed)
    }

    func test_send_resetRetried_afterFailure_retriesReset() async {
        // Given
        mockUseCase.result = false
        mockResetAppData.executeError = NSError(domain: "LaunchViewModelTests", code: 1)
        sut.send(.viewAppeared)
        await waitForLaunch()
        mockResetAppData.executeError = nil

        // When
        sut.send(.resetRetried)
        await waitForLaunch()

        // Then
        XCTAssertEqual(sut.state, .onboarding)
    }

    func test_send_viewAppeared_onboardingCompleted_setsHomeState() async {
        // Given
        mockUseCase.result = true

        // When
        sut.send(.viewAppeared)
        await waitForLaunch()

        // Then
        XCTAssertEqual(sut.state, .home)
    }

    func test_send_viewAppeared_withLaunchDelay_keepsLoadingStateUntilDelayFinishes() {
        // Given
        mockUseCase.result = true
        sut = LaunchViewModel(
            checkOnboardingUseCase: mockUseCase,
            resetAppDataUseCase: mockResetAppData,
            configureVoticeUseCase: NoOpConfigureVoticeUseCase(),
            attachmentMigrationUseCase: mockAttachmentMigration,
            remoteConfigManager: mockRemoteConfigManager,
            settingsManager: MockSettingsManager(),
            announcementSession: LaunchAnnouncementSession(),
            currentVersion: "1.0.0",
            launchDelay: .milliseconds(500)
        )

        // When
        sut.send(.viewAppeared)

        // Then
        XCTAssertEqual(sut.state, .loading)
    }

    func test_send_viewAppeared_onboardingCompleted_doesNotResetAppData() async {
        // Given
        mockUseCase.result = true

        // When
        sut.send(.viewAppeared)
        await waitForLaunch()

        // Then
        XCTAssertFalse(mockResetAppData.executeCalled)
    }

    func test_send_onboardingCompleted_setsHomeState() {
        // Given
        sut = LaunchViewModel(
            state: .onboarding,
            checkOnboardingUseCase: mockUseCase,
            resetAppDataUseCase: mockResetAppData,
            configureVoticeUseCase: NoOpConfigureVoticeUseCase(),
            attachmentMigrationUseCase: mockAttachmentMigration,
            remoteConfigManager: mockRemoteConfigManager,
            settingsManager: MockSettingsManager(),
            announcementSession: LaunchAnnouncementSession(),
            currentVersion: "1.0.0",
            launchDelay: .zero
        )

        // When
        sut.send(.onboardingCompleted)

        // Then
        XCTAssertEqual(sut.state, .home)
    }

    func test_send_viewAppeared_triggersAttachmentMigration() {
        // Given
        mockUseCase.result = true

        // When
        sut.send(.viewAppeared)

        // Then
        XCTAssertEqual(mockAttachmentMigration.executeCallCount, 1)
    }

    func test_send_viewAppeared_forceUpdateEnabledForNewerVersion_setsForceUpdateState() async {
        // Given
        mockUseCase.result = true
        mockRemoteConfigManager.result = .success(.stub(isForceUpdate: true, latestVersion: "1.1.0"))

        // When
        sut.send(.viewAppeared)
        await waitForLaunch()

        // Then
        guard case .forceUpdate(let update) = sut.state else {
            return XCTFail("Expected force update state")
        }
        XCTAssertEqual(update.latestVersion, "1.1.0")
        XCTAssertNil(sut.availableUpdate)
    }

    func test_send_viewAppeared_optionalUpdateAvailable_setsHomeStateAndAvailableUpdate() async {
        // Given
        mockUseCase.result = true
        mockRemoteConfigManager.result = .success(.stub(isForceUpdate: false, latestVersion: "1.1.0"))

        // When
        sut.send(.viewAppeared)
        await waitForLaunch()

        // Then
        XCTAssertEqual(sut.state, .home)
        XCTAssertEqual(sut.availableUpdate?.latestVersion, "1.1.0")
    }

    func test_send_viewAppeared_currentVersionIsNewer_setsHomeState() async {
        // Given
        mockUseCase.result = true
        mockRemoteConfigManager.result = .success(.stub(isForceUpdate: true, latestVersion: "0.9.0"))

        // When
        sut.send(.viewAppeared)
        await waitForLaunch()

        // Then
        XCTAssertEqual(sut.state, .home)
        XCTAssertNil(sut.availableUpdate)
    }

    func test_send_viewAppeared_maintenanceEnabled_setsMaintenanceState() async {
        // Given
        mockUseCase.result = true
        mockRemoteConfigManager.result = .success(.stub(isMaintenanceEnabled: true))

        // When
        sut.send(.viewAppeared)
        await waitForLaunch()

        // Then
        XCTAssertEqual(sut.state, .maintenance)
        XCTAssertNil(sut.availableUpdate)
    }

    func test_send_viewAppeared_maintenanceAndForceUpdateEnabled_setsMaintenanceState() async {
        // Given
        mockUseCase.result = true
        mockRemoteConfigManager.result = .success(
            .stub(isMaintenanceEnabled: true, isForceUpdate: true, latestVersion: "1.1.0")
        )

        // When
        sut.send(.viewAppeared)
        await waitForLaunch()

        // Then
        XCTAssertEqual(sut.state, .maintenance)
        XCTAssertNil(sut.availableUpdate)
    }

    func test_send_availableUpdateDismissed_availableUpdateExists_clearsAvailableUpdate() async {
        // Given
        mockUseCase.result = true
        mockRemoteConfigManager.result = .success(.stub(latestVersion: "1.1.0"))
        sut.send(.viewAppeared)
        await waitForLaunch()

        // When
        sut.send(.availableUpdateDismissed)

        // Then
        XCTAssertNil(sut.availableUpdate)
    }

    func test_send_onboardingCompleted_optionalUpdateAvailable_keepsUpdateForHome() async {
        // Given
        mockUseCase.result = false
        mockRemoteConfigManager.result = .success(.stub(latestVersion: "1.1.0"))
        sut.send(.viewAppeared)
        await waitForLaunch()

        // When
        sut.send(.onboardingCompleted)

        // Then
        XCTAssertEqual(sut.state, .home)
        XCTAssertEqual(sut.availableUpdate?.latestVersion, "1.1.0")
    }
}

// MARK: - Private

private extension LaunchViewModelTests {
    func waitForLaunch() async {
        guard let launch = sut.launchTask else { return XCTFail("Expected a launch task") }
        await launch.value
    }
}
