//
//  LaunchWhatsNewTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 24/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class LaunchWhatsNewTests: XCTestCase {
    func test_finishLaunch_requiredUpdateOrMaintenance_doesNotPresentAnnouncements() {
        for maintenance in [false, true] {
            let settings = MockSettingsManager()
            let sut = makeLaunch(settings: settings)
            let config = makeConfig(latestVersion: "3.0", forceUpdate: true, maintenance: maintenance)

            sut.finishLaunch(remoteConfig: config, isOnboardingCompleted: true)

            XCTAssertEqual(sut.state, maintenance ? .maintenance : .forceUpdate(config.appUpdate.ios))
            XCTAssertNil(sut.remoteWhatsNew)
            XCTAssertNil(sut.remoteBanner)
            XCTAssertTrue(settings.seenWhatsNewIDs.isEmpty)
        }
    }

    func test_finishLaunch_optionalUpdateAndWhatsNewAvailable_prioritizesUpdate() {
        let settings = MockSettingsManager()
        let sut = makeLaunch(settings: settings)

        sut.finishLaunch(remoteConfig: makeConfig(latestVersion: "3.0"), isOnboardingCompleted: true)

        XCTAssertEqual(sut.state, .home)
        XCTAssertEqual(sut.availableUpdate?.latestVersion, "3.0")
        XCTAssertNil(sut.remoteWhatsNew)
        sut.send(.availableUpdateDismissed)
        XCTAssertNil(sut.remoteWhatsNew)
        XCTAssertTrue(settings.seenWhatsNewIDs.isEmpty)
    }

    func test_finishLaunch_freshInstall_skipsWhatsNewUntilInstalledVersionChanges() {
        let settings = MockSettingsManager()
        let firstLaunch = makeLaunch(settings: settings)
        firstLaunch.finishLaunch(remoteConfig: makeConfig(), isOnboardingCompleted: false)
        XCTAssertEqual(firstLaunch.state, .onboarding)
        XCTAssertNil(firstLaunch.remoteWhatsNew)

        firstLaunch.send(.onboardingCompleted)
        XCTAssertEqual(firstLaunch.state, .home)
        XCTAssertNil(firstLaunch.remoteWhatsNew)
        XCTAssertEqual(settings.freshInstallVersion, "2.0")

        let relaunch = makeLaunch(settings: settings)
        relaunch.finishLaunch(remoteConfig: makeConfig(id: "later-campaign"), isOnboardingCompleted: true)
        XCTAssertNil(relaunch.remoteWhatsNew)

        let upgrade = makeLaunch(settings: settings, version: "2.1")
        upgrade.finishLaunch(remoteConfig: makeConfig(id: "upgrade", version: "2.1"), isOnboardingCompleted: true)
        XCTAssertEqual(upgrade.remoteWhatsNew?.id, "upgrade")
    }

    func test_finishLaunch_twoWindows_shareOnePresentationAndSuppressBannerUntilNextSession() {
        let settings = MockSettingsManager()
        let session = LaunchAnnouncementSession()
        let config = makeConfig()
        let first = makeLaunch(settings: settings, session: session)
        let second = makeLaunch(settings: settings, session: session)

        first.finishLaunch(remoteConfig: config, isOnboardingCompleted: true)
        second.finishLaunch(remoteConfig: config, isOnboardingCompleted: true)
        XCTAssertEqual(first.remoteWhatsNew?.id, "release-2")
        XCTAssertNil(first.remoteBanner)
        XCTAssertNil(second.remoteWhatsNew)
        XCTAssertNil(second.remoteBanner)

        first.send(.remoteWhatsNewDismissed)
        XCTAssertNil(first.remoteWhatsNew)
        XCTAssertNil(first.remoteBanner)
        let laterWindow = makeLaunch(settings: settings, session: session)
        laterWindow.finishLaunch(remoteConfig: config, isOnboardingCompleted: true)
        XCTAssertNil(laterWindow.remoteBanner)
        XCTAssertNil(laterWindow.remoteWhatsNew)

        let nextSession = makeLaunch(settings: settings)
        nextSession.finishLaunch(remoteConfig: config, isOnboardingCompleted: true)
        XCTAssertNil(nextSession.remoteWhatsNew)
        XCTAssertEqual(nextSession.remoteBanner?.id, "banner")

        nextSession.send(.remoteBannerDismissed)
        let afterBannerDismissal = makeLaunch(settings: settings)
        afterBannerDismissal.finishLaunch(remoteConfig: config, isOnboardingCompleted: true)
        XCTAssertNil(afterBannerDismissal.remoteBanner)
    }

    func test_send_viewDisappearedBeforeNewsAppears_releasesReservationForAnotherWindow() {
        let settings = MockSettingsManager()
        let session = LaunchAnnouncementSession()
        let first = makeLaunch(settings: settings, session: session)
        let second = makeLaunch(settings: settings, session: session)
        let config = makeConfig()
        first.finishLaunch(remoteConfig: config, isOnboardingCompleted: true)
        XCTAssertEqual(first.remoteWhatsNew?.id, "release-2")

        first.send(.viewDisappeared)
        second.finishLaunch(remoteConfig: config, isOnboardingCompleted: true)

        XCTAssertNil(first.remoteWhatsNew)
        XCTAssertEqual(second.remoteWhatsNew?.id, "release-2")
        XCTAssertTrue(settings.seenWhatsNewIDs.isEmpty)
    }

    func test_send_viewDisappearedAfterNewsAppears_keepsAnnouncementsSuppressedInOtherWindows() {
        let settings = MockSettingsManager()
        let session = LaunchAnnouncementSession()
        let first = makeLaunch(settings: settings, session: session)
        first.finishLaunch(remoteConfig: makeConfig(), isOnboardingCompleted: true)
        XCTAssertEqual(first.remoteWhatsNew?.id, "release-2")
        first.send(.remoteWhatsNewAppeared)

        first.send(.viewDisappeared)
        let second = makeLaunch(settings: settings, session: session)
        second.finishLaunch(remoteConfig: makeConfig(id: "another-campaign"), isOnboardingCompleted: true)

        XCTAssertNil(second.remoteWhatsNew)
        XCTAssertNil(second.remoteBanner)
    }

    func test_finishLaunch_reviewAlreadyRequested_defersWhatsNewUntilNextSession() {
        let settings = MockSettingsManager()
        let session = LaunchAnnouncementSession()
        session.hasRequestedReview = true
        let sut = makeLaunch(settings: settings, session: session)
        let config = makeConfig()

        sut.finishLaunch(remoteConfig: config, isOnboardingCompleted: true)

        XCTAssertNil(sut.remoteWhatsNew)
        XCTAssertTrue(settings.seenWhatsNewIDs.isEmpty)
        let nextSession = makeLaunch(settings: settings)
        nextSession.finishLaunch(remoteConfig: config, isOnboardingCompleted: true)
        XCTAssertEqual(nextSession.remoteWhatsNew?.id, "release-2")
    }

    func test_send_remoteWhatsNewDismissed_keepsPreviouslySeenIDs() {
        let settings = MockSettingsManager()
        settings.seenWhatsNewIDs = ["earlier-campaign"]
        settings.dismissedRemoteBannerKey = "banner"
        let sut = makeLaunch(settings: settings)
        sut.finishLaunch(remoteConfig: makeConfig(), isOnboardingCompleted: true)
        XCTAssertEqual(sut.remoteWhatsNew?.id, "release-2")

        sut.send(.remoteWhatsNewDismissed)

        XCTAssertEqual(settings.seenWhatsNewIDs, ["earlier-campaign", "release-2"])
        let relaunch = makeLaunch(settings: settings)
        relaunch.finishLaunch(remoteConfig: makeConfig(id: "earlier-campaign"), isOnboardingCompleted: true)
        XCTAssertNil(relaunch.remoteWhatsNew)
        XCTAssertNil(relaunch.remoteBanner)
    }

    func test_finishLaunch_pendingShortcut_preservesNewsForALaterLaunch() {
        let settings = MockSettingsManager()
        let session = LaunchAnnouncementSession { true }
        let sut = makeLaunch(settings: settings, session: session)
        sut.finishLaunch(remoteConfig: makeConfig(), isOnboardingCompleted: true)

        XCTAssertNil(sut.remoteWhatsNew)
        XCTAssertTrue(settings.seenWhatsNewIDs.isEmpty)
    }

    func test_send_externalEntryInAnotherWindow_defersVisibleNewsWithoutAcknowledgingIt() {
        let settings = MockSettingsManager()
        let session = LaunchAnnouncementSession()
        let first = makeLaunch(settings: settings, session: session)
        let second = makeLaunch(settings: settings, session: session)
        first.finishLaunch(remoteConfig: makeConfig(), isOnboardingCompleted: true)
        XCTAssertNotNil(first.remoteWhatsNew)

        second.send(.externalEntryRequested)
        first.send(.remoteWhatsNewDismissed)

        XCTAssertNil(first.remoteWhatsNew)
        XCTAssertNil(first.remoteBanner)
        XCTAssertTrue(settings.seenWhatsNewIDs.isEmpty)
    }

    func test_send_externalEntryBeforeOrDuringPresentation_defersWhatsNewWithoutConsumingID() {
        for duringPresentation in [false, true] {
            let settings = MockSettingsManager()
            let config = makeConfig()
            let sut = makeLaunch(settings: settings)

            if duringPresentation {
                sut.finishLaunch(remoteConfig: config, isOnboardingCompleted: true)
                XCTAssertEqual(sut.remoteWhatsNew?.id, "release-2")
                sut.send(.externalEntryRequested)
            } else {
                sut.send(.externalEntryRequested)
                sut.finishLaunch(remoteConfig: config, isOnboardingCompleted: true)
            }

            XCTAssertNil(sut.remoteWhatsNew)
            sut.send(.remoteWhatsNewDismissed)
            XCTAssertTrue(settings.seenWhatsNewIDs.isEmpty)
            let nextSession = makeLaunch(settings: settings)
            nextSession.finishLaunch(remoteConfig: config, isOnboardingCompleted: true)
            XCTAssertEqual(nextSession.remoteWhatsNew?.id, "release-2")
        }
    }
}

private extension LaunchWhatsNewTests {
    func makeLaunch(
        settings: MockSettingsManager,
        version: String = "2.0",
        session: LaunchAnnouncementSession = LaunchAnnouncementSession()
    ) -> LaunchViewModel {
        LaunchViewModel(
            checkOnboardingUseCase: MockCheckOnboardingUseCase(),
            resetAppDataUseCase: MockResetAppDataUseCase(),
            configureVoticeUseCase: NoOpConfigureVoticeUseCase(),
            attachmentMigrationUseCase: MockAttachmentMigrationUseCase(),
            remoteConfigManager: MockRemoteConfigManager(),
            settingsManager: settings,
            announcementSession: session,
            currentVersion: version,
            localeIdentifier: "en"
        )
    }

    func makeConfig(
        id: String = "release-2",
        version: String = "2.0",
        latestVersion: String = "2.0",
        forceUpdate: Bool = false,
        maintenance: Bool = false
    ) -> RemoteConfig {
        let stub = RemoteConfig.stub(
            isMaintenanceEnabled: maintenance, isForceUpdate: forceUpdate, latestVersion: latestVersion
        )
        let bannerItem = RemoteConfig.Item(
            title: "Banner", subtitle: "", cta: "Close", action: .close, url: "", emoji: ""
        )
        let highlight = RemoteWhatsNew.Highlight(symbol: "star", title: "Search", body: "Find conversations.")
        return RemoteConfig(
            schemaVersion: stub.schemaVersion,
            maintenanceMode: stub.maintenanceMode,
            appUpdate: stub.appUpdate,
            banner: .init(
                active: true, dismissBannerKey: "banner", platforms: [.ios, .macos], items: ["en": bannerItem]
            ),
            settingsSection: stub.settingsSection,
            whatsNew: .init(
                active: true, id: id, version: version, platforms: [.ios, .macos],
                items: ["en": .init(title: "What's new", highlights: [highlight], actionTitle: nil)],
                action: nil, url: nil
            )
        )
    }
}
