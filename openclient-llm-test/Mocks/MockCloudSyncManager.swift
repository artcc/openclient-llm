//
//  MockCloudSyncManager.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 31/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation
@testable import openclient_llm

// Safety: Repository tests inject one instance into one ConversationStorage actor and inspect it only after
// awaited calls.
// Other tests access their instance only from serialized @MainActor test methods.
final class MockCloudSyncManager: CloudSyncManagerProtocol, @unchecked Sendable {
    // MARK: - Properties

    var cloudAvailable: Bool = true
    var checkCloudAvailabilityCallCount = 0
    var checkCloudAvailabilityHandler: (@Sendable () async -> Bool)?
    var cloudConversations: [Conversation] = []
    var cloudIds: Set<UUID>?
    var syncedConversations: [Conversation] = []
    var deletedIds: [UUID] = []
    var deleteAllCalled: Bool = false
    var syncError: Error?
    var validationError: Error?
    var loadError: Error?
    var conversationLoadError: Error?
    var profileLoadError: Error?
    var memoryLoadError: Error?
    var templatesLoadError: Error?
    var cloudProfile: UserProfile?
    var cloudProfileDeletionMarker: CloudDeletionMarker?
    var savedProfile: UserProfile?
    var loadProfileCallCount = 0
    var loadProfileHandler: (@Sendable () async -> Void)?
    var loadMemoryCallCount = 0
    var loadTemplatesCallCount = 0
    var applyProfileCallCount = 0
    var applyProfileHandler: (() -> Void)?
    var cloudTemplates: [PromptTemplate] = []
    var cloudTemplateIds: Set<UUID>?
    var cloudTemplateDeletionMarkers: [UUID: CloudDeletionMarker] = [:]
    var syncedTemplates: [PromptTemplate] = []
    var deletedTemplateIds: [UUID] = []
    var applyTemplateDeletionCallCount = 0
    var applyTemplateDeletionHandler: (() -> Void)?
    var cloudMemoryItems: [MemoryItem]?
    var cloudMemoryDeletionMarkers: [CloudDeletionMarker] = []
    var savedMemoryItems: [MemoryItem]?
    var deleteMemoryCalled: Bool = false
    var pendingConversationDownloads: Bool = false
    var cloudTombstones: [ConversationTombstone] = []
    var cloudFolderState = ConversationFolderState()
    var cloudDeleteAllMarker: ConversationDeleteAllMarker?
    var cloudAttachmentData: [CloudAttachmentKey: Data] = [:]
    var materializedConversationIds: [UUID] = []
    var loadConversationsCallCount = 0
    var loadConversationsHandler: (() -> Void)?
    var loadConversationsSendableHandler: (@Sendable () -> Void)?
    var purgeMarker: CloudPurgeMarker?
    var purgeJournal: CloudPurgeJournal?
    var inventoryResult = CloudDataInventory(categories: [:])
    var deletionOutcomes: [CloudDataCategory: CloudDeletionCategoryOutcome] = [:]
    var requestedDeletionCategories: [Set<CloudDataCategory>] = []

    private let mockSession = CloudSyncSession(
        containerURL: URL(fileURLWithPath: "/mock-cloud"),
        identity: Data("mock-cloud".utf8)
    )
}

extension MockCloudSyncManager {

    // MARK: - Public

    func isCloudAvailable() -> Bool {
        cloudAvailable
    }

    func checkCloudAvailability() async -> Bool {
        checkCloudAvailabilityCallCount += 1
        if let checkCloudAvailabilityHandler { return await checkCloudAvailabilityHandler() }
        return cloudAvailable
    }

    func loadConversationSyncSnapshot() throws -> ConversationCloudSyncSnapshot {
        loadConversationsCallCount += 1
        loadConversationsHandler?()
        loadConversationsSendableHandler?()
        if let conversationLoadError { throw conversationLoadError }
        if let loadError { throw loadError }
        if pendingConversationDownloads { throw CloudSyncError.requiredDownloadPending }
        try requireCloudAvailable()
        let encoder = SyncJSONCoding.makeEncoder()
        let conversationData = try Dictionary(uniqueKeysWithValues: cloudConversations.map {
            ($0.id, try encoder.encode($0))
        })
        let decoder = SyncJSONCoding.makeDecoder()
        let canonicalConversations = try Dictionary(uniqueKeysWithValues: conversationData.map { id, data in
            (id, try decoder.decode(Conversation.self, from: data))
        })
        let tombstoneData = try Dictionary(uniqueKeysWithValues: cloudTombstones.map {
            ($0.conversationId, try encoder.encode($0))
        })
        return ConversationCloudSyncSnapshot(
            session: mockSession,
            manifestData: nil,
            conversations: canonicalConversations,
            conversationData: conversationData,
            tombstones: cloudTombstones,
            tombstoneData: tombstoneData,
            legacyTombstoneData: nil,
            deleteAllMarker: cloudDeleteAllMarker,
            deleteAllMarkerData: try cloudDeleteAllMarker.map { try encoder.encode($0) },
            attachmentData: cloudAttachmentData,
            attachmentPlaceholders: [],
            attachmentConversationIds: Set(cloudAttachmentData.keys.map(\.conversationId)),
            purgeMarker: purgeMarker,
            folderState: cloudFolderState
        )
    }

    func applyConversationSyncOutput(
        _ output: ConversationCloudSyncOutput,
        basedOn snapshot: ConversationCloudSyncSnapshot
    ) throws {
        if let syncError { throw syncError }
        try requireCloudAvailable()
        let outputIds = Set(output.conversations.map(\.id))
        deletedIds.append(contentsOf: Set(cloudConversations.map(\.id)).subtracting(outputIds))
        syncedConversations.append(contentsOf: output.conversations)
        cloudConversations = output.conversations
        cloudTombstones = output.tombstones
        cloudFolderState = output.folderState
        cloudDeleteAllMarker = output.deleteAllMarker
        cloudAttachmentData = output.attachments
    }

    func validateConversationSyncOutput(
        _ output: ConversationCloudSyncOutput,
        basedOn snapshot: ConversationCloudSyncSnapshot
    ) throws {
        if let validationError { throw validationError }
        try requireCloudAvailable()
    }

    func syncConversationsToCloud(_ conversations: [Conversation]) throws {
        if let syncError { throw syncError }
        try requireCloudAvailable()
        syncedConversations.append(contentsOf: conversations)
        for conversation in conversations {
            cloudConversations.removeAll { $0.id == conversation.id }
            cloudConversations.append(conversation)
        }
    }

    func loadConversationsFromCloud() throws -> [Conversation] {
        loadConversationsCallCount += 1
        loadConversationsHandler?()
        if let loadError { throw loadError }
        try requireCloudAvailable()
        return cloudConversations
    }

    func allCloudConversationIds() throws -> Set<UUID>? {
        try requireCloudAvailable()
        return cloudIds
    }

    func deleteConversationFromCloud(_ conversationId: UUID) throws {
        if let syncError { throw syncError }
        try requireCloudAvailable()
        deletedIds.append(conversationId)
        cloudConversations.removeAll { $0.id == conversationId }
    }

    func deleteAllFromCloud() throws {
        if let syncError { throw syncError }
        try requireCloudAvailable()
        deleteAllCalled = true
    }

    func hasPendingConversationDownloads() throws -> Bool {
        if let loadError { throw loadError }
        try requireCloudAvailable()
        return pendingConversationDownloads
    }

    func materializeAttachmentsFromCloud(for conversation: Conversation) throws -> Bool {
        if let loadError { throw loadError }
        try requireCloudAvailable()
        materializedConversationIds.append(conversation.id)
        return !pendingConversationDownloads
    }

    func loadConversationTombstonesFromCloud() throws -> [ConversationTombstone] {
        if let loadError { throw loadError }
        try requireCloudAvailable()
        return cloudTombstones
    }

    func saveConversationTombstonesToCloud(_ tombstones: [ConversationTombstone]) throws {
        if let syncError { throw syncError }
        try requireCloudAvailable()
        cloudTombstones = tombstones
    }

    func loadConversationDeleteAllMarkerFromCloud() throws -> ConversationDeleteAllMarker? {
        if let loadError { throw loadError }
        try requireCloudAvailable()
        return cloudDeleteAllMarker
    }

    func saveConversationDeleteAllMarkerToCloud(_ marker: ConversationDeleteAllMarker) throws {
        if let syncError { throw syncError }
        try requireCloudAvailable()
        cloudDeleteAllMarker = marker
    }

    func loadProfileSyncSnapshot() async throws -> CloudUserProfileSnapshot {
        loadProfileCallCount += 1
        await loadProfileHandler?()
        if let profileLoadError { throw profileLoadError }
        if let loadError { throw loadError }
        try requireCloudAvailable()
        let encoder = SyncJSONCoding.makeEncoder()
        let state: CloudUserProfileState
        let effectiveDeletionDate = [cloudProfileDeletionMarker?.deletedAt, purgeMarker?.deletedAt]
            .compactMap { $0 }
            .max()
        if let effectiveDeletionDate {
            if let cloudProfile, cloudProfile.modifiedAt > effectiveDeletionDate {
                state = .profile(cloudProfile)
            } else {
                state = .deleted(CloudDeletionMarker(
                    id: CloudSyncManager.profileMarkerId,
                    deletedAt: effectiveDeletionDate
                ))
            }
        } else {
            state = cloudProfile.map(CloudUserProfileState.profile) ?? .missing
        }
        return CloudUserProfileSnapshot(
            session: mockSession,
            state: state,
            profileData: try cloudProfile.map { try encoder.encode($0) },
            deletionMarkerData: try cloudProfileDeletionMarker.map { try encoder.encode($0) },
            purgeMarker: purgeMarker
        )
    }

    func applyProfileSyncOutput(
        _ output: CloudUserProfileSyncOutput,
        basedOn snapshot: CloudUserProfileSnapshot
    ) async throws {
        applyProfileCallCount += 1
        if let syncError { throw syncError }
        try requireCloudAvailable()
        applyProfileHandler?()
        let current = try await loadProfileSyncSnapshot()
        guard current.session == snapshot.session,
               current.profileData == snapshot.profileData,
              current.deletionMarkerData == snapshot.deletionMarkerData,
              current.purgeMarker == snapshot.purgeMarker else {
            throw CloudSyncError.cloudContentChanged
        }
        switch output {
        case .unchanged:
            break
        case .profile(let profile):
            savedProfile = profile
            cloudProfile = profile
        case .deleted(let marker):
            cloudProfileDeletionMarker = marker
            if let profile = cloudProfile, profile.modifiedAt <= marker.deletedAt {
                cloudProfile = nil
            }
        }
    }

    func loadTemplatesFromCloud() async throws -> PromptTemplateCloudSnapshot {
        loadTemplatesCallCount += 1
        if let templatesLoadError { throw templatesLoadError }
        if let loadError { throw loadError }
        try requireCloudAvailable()
        let encoder = SyncJSONCoding.makeEncoder()
        let decoder = SyncJSONCoding.makeDecoder()
        let rawData = try Dictionary(uniqueKeysWithValues: cloudTemplates.map {
            ($0.id, try encoder.encode($0))
        })
        let rawTemplates = try Dictionary(uniqueKeysWithValues: rawData.map { id, data in
            (id, try decoder.decode(PromptTemplate.self, from: data))
        })
        let markerData = try Dictionary(uniqueKeysWithValues: cloudTemplateDeletionMarkers.map { id, marker in
            (id, try encoder.encode(marker))
        })
        let markers = try Dictionary(uniqueKeysWithValues: markerData.map { id, data in
            (id, try decoder.decode(CloudDeletionMarker.self, from: data))
        })
        let templates = cloudTemplates.compactMap { rawTemplates[$0.id] }.filter { template in
            guard template.updatedAt > (purgeMarker?.deletedAt ?? .distantPast) else { return false }
            guard let marker = markers[template.id] else { return true }
            return template.updatedAt > marker.deletedAt
        }
        let data = rawData.filter { id, _ in templates.contains { $0.id == id } }
        return PromptTemplateCloudSnapshot(
            session: mockSession,
            templates: templates,
            templateData: data,
            rawTemplates: rawTemplates,
            staleTemplateIds: Set(rawTemplates.values.compactMap { template in
                guard let marker = markers[template.id],
                      template.updatedAt <= marker.deletedAt else { return nil }
                return template.id
            }),
            deletionMarkers: markers,
            templateDirectoryData: Dictionary(uniqueKeysWithValues: rawData.map {
                ("\($0.key.uuidString).json", $0.value)
            }),
            tombstoneDirectoryData: Dictionary(uniqueKeysWithValues: markerData.map {
                ("\($0.key.uuidString).json", $0.value)
            }),
            templateDirectoryExists: !rawData.isEmpty,
            tombstoneDirectoryExists: !markerData.isEmpty,
            purgeMarker: purgeMarker
        )
    }

    func applyTemplateUploads(
        _ templates: [PromptTemplate],
        basedOn snapshot: PromptTemplateCloudSnapshot
    ) async throws {
        if let syncError { throw syncError }
        try requireCloudAvailable()
        let current = try await loadTemplatesFromCloud()
        guard current.session == snapshot.session,
              current.templateDirectoryData == snapshot.templateDirectoryData,
              current.tombstoneDirectoryData == snapshot.tombstoneDirectoryData,
              current.templateDirectoryExists == snapshot.templateDirectoryExists,
              current.tombstoneDirectoryExists == snapshot.tombstoneDirectoryExists,
              current.purgeMarker == snapshot.purgeMarker else {
            throw CloudSyncError.cloudContentChanged
        }
        for template in templates {
            if let marker = cloudTemplateDeletionMarkers[template.id], template.updatedAt <= marker.deletedAt {
                throw CloudSyncError.cloudContentChanged
            }
            syncedTemplates.append(template)
            cloudTemplates.removeAll { $0.id == template.id }
            cloudTemplates.append(template)
        }
        cloudTemplateIds = Set(cloudTemplates.map(\.id))
    }

    func applyTemplateDeletion(
        _ marker: CloudDeletionMarker,
        basedOn snapshot: PromptTemplateCloudSnapshot
    ) async throws {
        applyTemplateDeletionCallCount += 1
        if let syncError { throw syncError }
        try requireCloudAvailable()
        applyTemplateDeletionHandler?()
        let current = try await loadTemplatesFromCloud()
        guard current.session == snapshot.session,
              current.templateDirectoryData == snapshot.templateDirectoryData,
              current.tombstoneDirectoryData == snapshot.tombstoneDirectoryData,
              current.templateDirectoryExists == snapshot.templateDirectoryExists,
              current.tombstoneDirectoryExists == snapshot.tombstoneDirectoryExists,
              current.purgeMarker == snapshot.purgeMarker else {
            throw CloudSyncError.cloudContentChanged
        }
        deletedTemplateIds.append(marker.id)
        let existingDate = cloudTemplateDeletionMarkers[marker.id]?.deletedAt ?? .distantPast
        let effectiveDate = max(existingDate, marker.deletedAt)
        cloudTemplateDeletionMarkers[marker.id] = CloudDeletionMarker(id: marker.id, deletedAt: effectiveDate)
        cloudTemplates.removeAll { $0.id == marker.id && $0.updatedAt <= effectiveDate }
        if !cloudTemplates.contains(where: { $0.id == marker.id }) {
            cloudTemplateIds?.remove(marker.id)
        }
    }

    func loadMemorySyncSnapshot() async throws -> MemoryCloudSyncSnapshot {
        loadMemoryCallCount += 1
        if let memoryLoadError { throw memoryLoadError }
        if let loadError { throw loadError }
        try requireCloudAvailable()
        let eligibleItems = cloudMemoryItems?.filter { item in
            guard item.updatedAt > (purgeMarker?.deletedAt ?? .distantPast) else { return false }
            guard let marker = cloudMemoryDeletionMarkers.first(where: { $0.id == item.id }) else { return true }
            return item.updatedAt > marker.deletedAt
        }
        let encoder = SyncJSONCoding.makeEncoder()
        return MemoryCloudSyncSnapshot(
            session: mockSession,
            items: eligibleItems,
            deletionMarkers: cloudMemoryDeletionMarkers,
            memoryData: try cloudMemoryItems.map { try encoder.encode($0) },
            deletionMarkerData: cloudMemoryDeletionMarkers.isEmpty
                ? nil
                : try encoder.encode(cloudMemoryDeletionMarkers),
            purgeMarker: purgeMarker
        )
    }

    func applyMemorySyncOutput(
        items: [MemoryItem],
        deletionMarkers: [CloudDeletionMarker],
        basedOn snapshot: MemoryCloudSyncSnapshot
    ) async throws {
        if let syncError { throw syncError }
        try requireCloudAvailable()
        let current = try await loadMemorySyncSnapshot()
        guard current.session == snapshot.session,
              current.memoryData == snapshot.memoryData,
              current.deletionMarkerData == snapshot.deletionMarkerData,
              current.purgeMarker == snapshot.purgeMarker else {
            throw CloudSyncError.cloudContentChanged
        }
        cloudMemoryDeletionMarkers = deletionMarkers
        savedMemoryItems = items
        cloudMemoryItems = items.filter { item in
            guard let marker = cloudMemoryDeletionMarkers.first(where: { $0.id == item.id }) else { return true }
            return item.updatedAt > marker.deletedAt
        }
    }

    func deleteMemoryItemFromCloud(_ itemId: UUID, deletedAt: Date) async throws {
        if let syncError { throw syncError }
        try requireCloudAvailable()
        let existingDate = cloudMemoryDeletionMarkers
            .first(where: { $0.id == itemId })?
            .deletedAt ?? .distantPast
        let effectiveDate = max(existingDate, deletedAt)
        cloudMemoryDeletionMarkers.removeAll { $0.id == itemId }
        cloudMemoryDeletionMarkers.append(CloudDeletionMarker(id: itemId, deletedAt: effectiveDate))
        cloudMemoryItems?.removeAll { $0.id == itemId && $0.updatedAt <= effectiveDate }
    }

    func loadCloudInventory() async -> CloudDataInventory {
        inventoryResult
    }

    func loadCloudPurgeMarker() async throws -> CloudPurgeMarker? {
        if let loadError { throw loadError }
        return purgeMarker
    }

    func loadCloudPurgeJournal() async throws -> CloudPurgeJournal? {
        if let loadError { throw loadError }
        return purgeJournal
    }

    func deleteCloudData(
        categories: Set<CloudDataCategory>,
        marker: CloudPurgeMarker?
    ) async throws -> CloudDeletionResult {
        if let syncError { throw syncError }
        requestedDeletionCategories.append(categories)
        let effectiveMarker = marker ?? CloudPurgeMarker(id: UUID(), deletedAt: Date())
        purgeMarker = effectiveMarker
        if purgeJournal?.marker != effectiveMarker {
            purgeJournal = CloudPurgeJournal(
                marker: effectiveMarker,
                categoryStates: Dictionary(
                    uniqueKeysWithValues: CloudDataCategory.allCases.map { ($0, .pending) }
                )
            )
        }
        let outcomes = Dictionary(uniqueKeysWithValues: categories.map {
            ($0, deletionOutcomes[$0] ?? .deleted)
        })
        for (category, outcome) in outcomes where outcome == .deleted {
            if purgeJournal?.categoryStates[category] == .pending {
                purgeJournal?.categoryStates[category] = .cloudCleanupCompleted
            }
        }
        return CloudDeletionResult(marker: effectiveMarker, outcomes: outcomes)
    }

    func completeLocalPurgeCleanup(category: CloudDataCategory, marker: CloudPurgeMarker) async throws {
        guard purgeJournal?.marker == marker else { throw CloudSyncError.cloudContentChanged }
        purgeJournal?.categoryStates[category] = .completed
    }

    // MARK: - Private

    private func requireCloudAvailable() throws {
        guard cloudAvailable else { throw CloudSyncError.containerUnavailable }
    }

}
