//
//  LaunchViewModel.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

@Observable
@MainActor
final class LaunchViewModel {
    // MARK: - Properties

    enum Event {
        case viewAppeared
        case viewDisappeared
        case onboardingCompleted
        case availableUpdateDismissed
        case remoteBannerDismissed
        case remoteWhatsNewDismissed
        case remoteWhatsNewAppeared
        case externalEntryRequested
        case resetRetried
    }

    enum State: Equatable {
        case loading
        case onboarding
        case home
        case maintenance
        case forceUpdate(RemoteConfig.PlatformUpdate)
        case resetFailed
    }

    private(set) var state: State
    private(set) var availableUpdate: RemoteConfig.PlatformUpdate?
    private(set) var remoteBanner: RemoteBanner?
    private(set) var launchTask: Task<Void, Never>?
    var remoteWhatsNew: RemoteWhatsNew? { announcementSession.hasExternalEntry ? nil : selectedNews }

    private var selectedNews: RemoteWhatsNew?
    private let announcementSession: LaunchAnnouncementSession
    private var hasStartedLaunch = false
    private var hasPresentedNews = false
    private var initialReset: Task<Void, Error>?
    private let checkOnboardingUseCase: CheckOnboardingUseCaseProtocol
    private let resetAppDataUseCase: ResetAppDataUseCaseProtocol
    private let configureVoticeUseCase: ConfigureVoticeUseCaseProtocol
    private let attachmentMigrationUseCase: AttachmentMigrationUseCaseProtocol
    private let remoteConfigManager: RemoteConfigManagerProtocol
    private let settingsManager: SettingsManagerProtocol
    private let currentVersion: String?
    private let localeIdentifier: String
    private let launchDelay: Duration

    // MARK: - Init

    init(
        state: State = .loading,
        checkOnboardingUseCase: CheckOnboardingUseCaseProtocol = CheckOnboardingUseCase(),
        resetAppDataUseCase: ResetAppDataUseCaseProtocol = ResetAppDataUseCase(),
        configureVoticeUseCase: ConfigureVoticeUseCaseProtocol = ConfigureVoticeUseCase(),
        attachmentMigrationUseCase: AttachmentMigrationUseCaseProtocol = AttachmentMigrationUseCase(),
        remoteConfigManager: RemoteConfigManagerProtocol = RemoteConfigManager.shared,
        settingsManager: SettingsManagerProtocol = SettingsManager(),
        announcementSession: LaunchAnnouncementSession = .shared,
        currentVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
        localeIdentifier: String = Locale.current.identifier,
        launchDelay: Duration = .milliseconds(1000)
    ) {
        self.state = state
        self.checkOnboardingUseCase = checkOnboardingUseCase
        self.resetAppDataUseCase = resetAppDataUseCase
        self.configureVoticeUseCase = configureVoticeUseCase
        self.attachmentMigrationUseCase = attachmentMigrationUseCase
        self.remoteConfigManager = remoteConfigManager
        self.settingsManager = settingsManager
        self.announcementSession = announcementSession
        self.currentVersion = currentVersion
        self.localeIdentifier = localeIdentifier
        self.launchDelay = launchDelay
    }

    // MARK: - Input functions

    func send(_ event: Event) {
        switch event {
        case .viewAppeared:
            beginLaunch()
        case .viewDisappeared:
            endPresentation()
        case .onboardingCompleted:
            state = .home
        case .availableUpdateDismissed:
            availableUpdate = nil
        case .remoteBannerDismissed:
            dismissBanner()
        case .remoteWhatsNewDismissed:
            acknowledgeNews()
        case .remoteWhatsNewAppeared:
            hasPresentedNews = remoteWhatsNew != nil
        case .externalEntryRequested:
            announcementSession.hasExternalEntry = true
            selectedNews = nil
        case .resetRetried:
            initialReset = nil
            state = .loading
            startLaunch(isOnboardingCompleted: false)
        }
    }

    // MARK: - Private functions

    private func dismissBanner() {
        guard let remoteBanner else { return }
        settingsManager.setDismissedRemoteBannerKey(remoteBanner.id)
        self.remoteBanner = nil
    }

    private func acknowledgeNews() {
        guard let remoteWhatsNew else { return }
        settingsManager.seenWhatsNewIDs.insert(remoteWhatsNew.id)
        selectedNews = nil
    }

    func configureVotice() {
        do {
            try configureVoticeUseCase.execute(userIsPremium: false)
        } catch {
            LogManager.error("LaunchViewModel: configureVoticeUseCase: execute: error: \(error)")
        }
    }

    private func beginLaunch() {
        guard !hasStartedLaunch else { return }
        hasStartedLaunch = true
        configureVotice()
        attachmentMigrationUseCase.execute()
        startLaunch(isOnboardingCompleted: checkOnboardingUseCase.execute())
    }

    private func endPresentation() {
        launchTask?.cancel()
        launchTask = nil
        if selectedNews != nil, !hasPresentedNews {
            announcementSession.presentation = .undecided
            selectedNews = nil
            hasStartedLaunch = false
        } else if state == .loading {
            hasStartedLaunch = false
        }
    }

    private func startLaunch(isOnboardingCompleted: Bool) {
        if !isOnboardingCompleted, initialReset == nil {
            // Once cleanup starts, closing the window must not cancel it between stores.
            initialReset = Task { [resetAppDataUseCase] in try await resetAppDataUseCase.execute() }
        }
        launchTask = Task {
            do {
                if !isOnboardingCompleted { try await initialReset?.value }
            } catch {
                guard !Task.isCancelled else { return }
                LogManager.error("Initial app data reset failed")
                state = .resetFailed
                return
            }
            guard !Task.isCancelled else { return }
            async let launchDelayCompleted: Void = Self.waitForLaunchDelay(launchDelay)
            let remoteConfig = await loadRemoteConfig()
            await launchDelayCompleted
            guard !Task.isCancelled else { return }
            finishLaunch(remoteConfig: remoteConfig, isOnboardingCompleted: isOnboardingCompleted)
        }
    }

    func loadRemoteConfig() async -> RemoteConfig? {
        do {
            let config = try await remoteConfigManager.loadConfig()
            LogManager.info("LaunchViewModel: Remote Config loaded")
            return config
        } catch {
            LogManager.error("LaunchViewModel: Remote Config load failed: \(error)")
            return nil
        }
    }

    func finishLaunch(remoteConfig: RemoteConfig?, isOnboardingCompleted: Bool) {
        availableUpdate = nil
        remoteBanner = nil
        let update = availableUpdate(from: remoteConfig)
        if !isOnboardingCompleted {
            settingsManager.freshInstallVersion = currentVersion
        }

        if remoteConfig?.maintenanceMode.enabled == true {
            state = .maintenance
        } else if let update, update.forceUpdate {
            state = .forceUpdate(update)
        } else {
            availableUpdate = update
            selectAnnouncement(from: remoteConfig, allowsNews: isOnboardingCompleted && update == nil)
            state = isOnboardingCompleted ? .home : .onboarding
        }
    }

    private func selectAnnouncement(from config: RemoteConfig?, allowsNews: Bool) {
        guard announcementSession.presentation != .whatsNew else { return }
        if allowsNews, announcementSession.canPresentNews, let currentVersion,
           let news = config?.resolvedWhatsNew(
               installedVersion: currentVersion, platform: platform, localeIdentifier: localeIdentifier
           ),
           settingsManager.freshInstallVersion != news.version,
           !settingsManager.seenWhatsNewIDs.contains(news.id) {
            selectedNews = news
            announcementSession.presentation = .whatsNew
        } else if let banner = availableBanner(from: config) {
            remoteBanner = banner
            announcementSession.presentation = .banner
        }
    }

    private var platform: RemoteConfig.Platform {
#if os(iOS)
        .ios
#else
        .macos
#endif
    }

    func availableUpdate(from remoteConfig: RemoteConfig?) -> RemoteConfig.PlatformUpdate? {
        guard let remoteConfig, let currentVersion else { return nil }

#if os(iOS)
        let update = remoteConfig.appUpdate.ios
#else
        let update = remoteConfig.appUpdate.macos
#endif

        guard update.enabled else { return nil }
        guard currentVersion.compare(update.latestVersion, options: .numeric) == .orderedAscending else { return nil }
        return update
    }

    func availableBanner(from remoteConfig: RemoteConfig?) -> RemoteBanner? {
        guard let banner = remoteConfig?.banner, banner.active else { return nil }

        guard banner.platforms.contains(platform) else { return nil }
        guard settingsManager.getDismissedRemoteBannerKey() != banner.dismissBannerKey else { return nil }
        guard let item = localizedBannerItem(from: banner.items) else { return nil }
        return RemoteBanner(id: banner.dismissBannerKey, item: item)
    }

    func localizedBannerItem(from items: [String: RemoteConfig.Item]) -> RemoteConfig.Item? {
        for candidate in RemoteConfig.languageCandidates(for: localeIdentifier) {
            if let item = items.first(where: { $0.key.caseInsensitiveCompare(candidate) == .orderedSame })?.value {
                return item
            }
        }
        return nil
    }

    nonisolated static func waitForLaunchDelay(_ launchDelay: Duration) async {
        guard launchDelay > .zero else { return }
        try? await Task.sleep(for: launchDelay)
    }
}
