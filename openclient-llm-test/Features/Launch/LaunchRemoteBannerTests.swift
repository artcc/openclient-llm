//
//  LaunchRemoteBannerTests.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 09/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class LaunchRemoteBannerTests: XCTestCase {
    // MARK: - Properties

    private var sut: LaunchViewModel!
    private var mockRemoteConfigManager: MockRemoteConfigManager!
    private var mockSettingsManager: MockSettingsManager!

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()

        mockRemoteConfigManager = MockRemoteConfigManager()
        mockSettingsManager = MockSettingsManager()
        let mockCheckOnboardingUseCase = MockCheckOnboardingUseCase()
        mockCheckOnboardingUseCase.result = true
        sut = LaunchViewModel(
            checkOnboardingUseCase: mockCheckOnboardingUseCase,
            resetAppDataUseCase: MockResetAppDataUseCase(),
            configureVoticeUseCase: NoOpConfigureVoticeUseCase(),
            attachmentMigrationUseCase: MockAttachmentMigrationUseCase(),
            remoteConfigManager: mockRemoteConfigManager,
            settingsManager: mockSettingsManager,
            announcementSession: LaunchAnnouncementSession(),
            currentVersion: "1.0.0",
            localeIdentifier: "es-ES",
            launchDelay: .zero
        )
    }

    override func tearDown() async throws {
        sut = nil
        mockRemoteConfigManager = nil
        mockSettingsManager = nil

        try await super.tearDown()
    }

    // MARK: - Tests

    func test_send_viewAppeared_activeBanner_usesCurrentLanguage() async {
        // Given
        mockRemoteConfigManager.result = .success(.stub(banner: makeBanner()))

        // When
        sut.send(.viewAppeared)
        await waitForLaunch()

        // Then
        XCTAssertEqual(sut.remoteBanner?.item.title, "Novedades")
    }

    func test_send_viewAppeared_currentLanguageMissing_usesEnglishFallback() async {
        // Given
        let banner = makeBanner(items: ["en": makeItem(title: "News")])
        mockRemoteConfigManager.result = .success(.stub(banner: banner))

        // When
        sut.send(.viewAppeared)
        await waitForLaunch()

        // Then
        XCTAssertEqual(sut.remoteBanner?.item.title, "News")
    }

    func test_send_viewAppeared_bannerDismissed_doesNotExposeBanner() async {
        // Given
        mockSettingsManager.dismissedRemoteBannerKey = "banner-1"
        mockRemoteConfigManager.result = .success(.stub(banner: makeBanner()))

        // When
        sut.send(.viewAppeared)
        await waitForLaunch()

        // Then
        XCTAssertNil(sut.remoteBanner)
    }

    func test_send_viewAppeared_platformNotIncluded_doesNotExposeBanner() async {
        // Given
        let banner = makeBanner(platforms: [.macos])
        mockRemoteConfigManager.result = .success(.stub(banner: banner))

        // When
        sut.send(.viewAppeared)
        await waitForLaunch()

        // Then
        XCTAssertNil(sut.remoteBanner)
    }

    func test_send_remoteBannerDismissed_visibleBanner_persistsKeyAndClearsBanner() async {
        // Given
        mockRemoteConfigManager.result = .success(.stub(banner: makeBanner()))
        sut.send(.viewAppeared)
        await waitForLaunch()

        // When
        sut.send(.remoteBannerDismissed)

        // Then
        XCTAssertEqual(mockSettingsManager.dismissedRemoteBannerKey, "banner-1")
        XCTAssertNil(sut.remoteBanner)
    }
}

// MARK: - Private

private extension LaunchRemoteBannerTests {
    func makeBanner(
        platforms: [RemoteConfig.Platform] = [.ios, .macos],
        items: [String: RemoteConfig.Item]? = nil
    ) -> RemoteConfig.Banner {
        RemoteConfig.Banner(
            active: true,
            dismissBannerKey: "banner-1",
            platforms: platforms,
            items: items ?? [
                "en": makeItem(title: "News"),
                "es": makeItem(title: "Novedades")
            ]
        )
    }

    func makeItem(title: String) -> RemoteConfig.Item {
        RemoteConfig.Item(
            title: title,
            subtitle: "Subtitle",
            cta: "Close",
            action: .close,
            url: "",
            emoji: ""
        )
    }

    func waitForLaunch() async {
        guard let launch = sut.launchTask else { return XCTFail("Expected a launch task") }
        await launch.value
    }
}
