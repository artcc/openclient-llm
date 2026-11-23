//
//  ConversationCloudObserver.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 12/07/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

@MainActor
protocol CloudSyncRuntimeCoordinating: AnyObject {
    func start(profileConflictHandler: (() -> Void)?)
    func approveCurrentAccount(profileConflictHandler: (() -> Void)?)
    func stop()
}

extension CloudSyncRuntimeCoordinating {
    func start() {
        start(profileConflictHandler: nil)
    }

    func approveCurrentAccount() {
        approveCurrentAccount(profileConflictHandler: nil)
    }
}

@MainActor
final class ConversationCloudObserver: CloudSyncRuntimeCoordinating {
    struct StartContext {
        let approvingCurrentAccount: Bool
        let approvalFingerprint: String?
        let generation: Int
        let runtimeGeneration: Int
    }

    // MARK: - Properties

    static let synchronizedPathComponents = [
        "SyncManifest.json",
        "CloudPurgeMarker.json",
        "UserProfile.json",
        "UserProfileDeletion.json",
        "Memory.json",
        "MemoryTombstones.json",
        "/PromptTemplates",
        "/PromptTemplateTombstones",
        "/Conversations",
        "/\(ConversationFolderState.foldersDirectory)",
        "/\(ConversationFolderState.membershipsDirectory)",
        "/\(ConversationFolderState.tombstonesDirectory)",
        "/ConversationTombstones",
        "ConversationTombstones.json",
        "ConversationDeleteAll.json",
        "/Attachments"
    ]
    static let shared = ConversationCloudObserver()

    let settingsManager: SettingsManagerProtocol
    let cloudSyncManager: CloudSyncManagerProtocol
    let synchronizeAppDataUseCase: SynchronizeAppDataUseCaseProtocol
    let enableCloudSyncUseCase: EnableCloudSyncUseCaseProtocol
    let notificationCenter: NotificationCenter
    let metadataReadiness: CloudMetadataReadiness
    let containerProvider: CloudContainerProviding
    let fileManager: FileManager
    let metadataDebounceDuration: Duration
    let runtimeStore: CloudSyncRuntimeStoreProtocol
    let accountAssociation: CloudAccountAssociationProtocol
    var metadataQuery: NSMetadataQuery?
    var metadataSession: CloudSyncSession?
    var queryObservers: [NSObjectProtocol] = []
    var lifecycleObservers: [NSObjectProtocol] = []
    var contentFingerprints: [String: ContentFingerprint] = [:]
    var hasEstablishedBaseline = false
    var synchronizationTask: Task<Void, Never>?
    var cancellationTask: Task<Void, Never>?
    var metadataDebounceTask: Task<Void, Never>?
    var startTask: Task<Void, Never>?
    var needsSynchronization = false
    var synchronizationGeneration = 0
    var startGeneration = 0
    var runtimeGeneration = 0
    var profileConflictHandler: (() -> Void)?
    var startContext: StartContext?

    // MARK: - Init

    init(
        settingsManager: SettingsManagerProtocol = SettingsManager(),
        cloudSyncManager: CloudSyncManagerProtocol = CloudSyncManager(),
        synchronizeAppDataUseCase: SynchronizeAppDataUseCaseProtocol = SynchronizeAppDataUseCase(),
        enableCloudSyncUseCase: EnableCloudSyncUseCaseProtocol = EnableCloudSyncUseCase(),
        notificationCenter: NotificationCenter = .default,
        metadataReadiness: CloudMetadataReadiness = .shared,
        containerProvider: CloudContainerProviding? = nil,
        fileManager: FileManager = .default,
        metadataDebounceDuration: Duration = .milliseconds(500),
        runtimeStore: CloudSyncRuntimeStoreProtocol = CloudSyncRuntimeStore.shared,
        accountAssociation: CloudAccountAssociationProtocol = CloudAccountAssociation.shared
    ) {
        self.settingsManager = settingsManager
        self.cloudSyncManager = cloudSyncManager
        self.synchronizeAppDataUseCase = synchronizeAppDataUseCase
        self.enableCloudSyncUseCase = enableCloudSyncUseCase
        self.notificationCenter = notificationCenter
        self.metadataReadiness = metadataReadiness
        self.containerProvider = containerProvider ?? UbiquityCloudContainerProvider(
            fileManager: fileManager,
            metadataReadiness: metadataReadiness
        )
        self.fileManager = fileManager
        self.metadataDebounceDuration = metadataDebounceDuration
        self.runtimeStore = runtimeStore
        self.accountAssociation = accountAssociation
        observeLifecycleChanges()
    }

    // MARK: - Public

    func start(profileConflictHandler: (() -> Void)? = nil) {
        start(approvingCurrentAccount: false, profileConflictHandler: profileConflictHandler)
    }

    func approveCurrentAccount(profileConflictHandler: (() -> Void)? = nil) {
        start(approvingCurrentAccount: true, profileConflictHandler: profileConflictHandler)
    }

    private func start(
        approvingCurrentAccount: Bool,
        profileConflictHandler: (() -> Void)?
    ) {
        guard settingsManager.getIsCloudSyncEnabled() else {
            stop()
            return
        }
        self.profileConflictHandler = profileConflictHandler
        startGeneration += 1
        let generation = startGeneration
        startTask?.cancel()
        resetObservation()
        guard approvingCurrentAccount || canStartForAssociatedAccount() else { return }
        let approvalFingerprint = approvingCurrentAccount ? accountAssociation.currentAccountFingerprint() : nil
        let runtimeGeneration = runtimeStore.begin(.checkingAvailability)
        self.runtimeGeneration = runtimeGeneration
        startContext = StartContext(
            approvingCurrentAccount: approvingCurrentAccount,
            approvalFingerprint: approvalFingerprint,
            generation: generation,
            runtimeGeneration: runtimeGeneration
        )
        let pendingCancellation = cancellationTask
        startTask = Task { [weak self] in
            await pendingCancellation?.value
            guard !Task.isCancelled else { return }
            guard let self else { return }
            let session = await resolveCurrentSession().value
            guard !Task.isCancelled else { return }
            completeStart(session: session, generation: generation, runtimeGeneration: runtimeGeneration)
        }
    }

    func stop() {
        startGeneration += 1
        startTask?.cancel()
        startTask = nil
        resetObservation()
        profileConflictHandler = nil
        runtimeStore.publish(settingsManager.getIsCloudSyncEnabled() ? .checkingAvailability : .disabled)
    }

    func handleMetadataChange() {
        guard hasEstablishedBaseline,
              let metadataSession,
              metadataReadiness.isReady(for: metadataSession) else { return }
        metadataDebounceTask?.cancel()
        metadataDebounceTask = Task { [weak self, metadataDebounceDuration] in
            try? await Task.sleep(for: metadataDebounceDuration)
            guard !Task.isCancelled, let self else { return }
            startSynchronization()
        }
    }

    func startSynchronization() {
        guard settingsManager.getIsCloudSyncEnabled(),
              hasEstablishedBaseline,
              let metadataSession,
              metadataReadiness.isReady(for: metadataSession) else { return }
        synchronizeDetectedChanges()
    }

    func synchronizeDetectedChanges() {
        guard settingsManager.getIsCloudSyncEnabled() else { return }
        guard synchronizationTask == nil else {
            needsSynchronization = true
            return
        }

        let generation = synchronizationGeneration
        let pendingCancellation = cancellationTask
        synchronizationTask = Task { [weak self] in
            guard let self else { return }
            await pendingCancellation?.value
            guard synchronizationGeneration == generation else { return }
            repeat {
                needsSynchronization = false
                let result = await synchronizeAppDataUseCase.execute()
                guard synchronizationGeneration == generation else { return }
                guard !Task.isCancelled,
                      settingsManager.getIsCloudSyncEnabled() else { break }
                notifyConsumers(for: result)
            } while needsSynchronization
            if synchronizationGeneration == generation {
                synchronizationTask = nil
            }
        }
    }

    static func requiresDownload(forDownloadingStatus status: String?) -> Bool {
        guard let status else { return false }
        return status != NSMetadataUbiquitousItemDownloadingStatusCurrent
    }

    isolated deinit {
        metadataReadiness.reset()
        metadataQuery?.stop()
        synchronizationTask?.cancel()
        cancellationTask?.cancel()
        metadataDebounceTask?.cancel()
        startTask?.cancel()
        for observer in queryObservers {
            notificationCenter.removeObserver(observer)
        }
        for observer in lifecycleObservers {
            notificationCenter.removeObserver(observer)
        }
    }
}
