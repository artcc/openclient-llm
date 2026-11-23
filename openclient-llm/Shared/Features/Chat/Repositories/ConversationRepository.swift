//
//  ConversationRepository.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 31/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation
import WidgetKit

protocol ConversationRepositoryProtocol: Sendable {
    func loadAll() async throws -> [Conversation]
    func loadLocal() async throws -> [Conversation]
    func loadBackupSnapshot() async throws -> ConversationBackupSnapshot
    @discardableResult
    func save(
        _ conversation: Conversation,
        expectedBase: Conversation?,
        creationPlacement: ConversationCreationPlacement?
    ) async throws -> Conversation
    func importBatch(
        _ conversations: [Conversation],
        organization: ConversationFolderSnapshot
    ) async throws -> [Conversation]
    func setPinned(_ isPinned: Bool, conversationId: UUID) async throws -> Conversation?
    func rename(_ conversationId: UUID, title: String) async throws -> Conversation?
    func updateTags(_ conversationId: UUID, tags: [ConversationTag]) async throws -> Conversation?
    func delete(_ conversationId: UUID) async throws
    func deleteSynchronized(_ conversationId: UUID) async throws
    func deleteAll() async throws
    @discardableResult
    func synchronize() async -> ConversationSyncResult
    func cancelSynchronization() async
    func cancelSynchronizationAndDeleteAll() async throws
    func purgeLocalData(through marker: CloudPurgeMarker) async throws
    func validateLocalReset() async throws
}

extension ConversationRepositoryProtocol {
    @discardableResult
    func save(_ conversation: Conversation, expectedBase: Conversation? = nil) async throws -> Conversation {
        try await save(conversation, expectedBase: expectedBase, creationPlacement: nil)
    }
}

struct ConversationRepository: ConversationRepositoryProtocol {
    // MARK: - Properties

    private static let liveStorage = ConversationStorage()
    private static let liveSyncCoordinator = ConversationSyncCoordinator(storage: liveStorage)

    private let settingsManager: SettingsManagerProtocol
    private let storage: ConversationStorage
    private let syncCoordinator: ConversationSyncCoordinator
    private let mutationGate: CloudSynchronizationMutationGate

    // MARK: - Init

    init(
        settingsManager: SettingsManagerProtocol = SettingsManager(),
        cloudSyncManager: CloudSyncManagerProtocol? = nil,
        attachmentRepository: AttachmentRepositoryProtocol? = nil,
        baseDirectory: URL? = nil,
        storage: ConversationStorage? = nil,
        syncCoordinator: ConversationSyncCoordinator? = nil,
        mutationGate: CloudSynchronizationMutationGate = .shared
    ) {
        self.settingsManager = settingsManager
        self.mutationGate = mutationGate
        if let storage {
            self.storage = storage
            self.syncCoordinator = syncCoordinator ?? ConversationSyncCoordinator(storage: storage)
        } else if baseDirectory != nil || cloudSyncManager != nil || attachmentRepository != nil {
            let manager = cloudSyncManager ?? CloudSyncManager()
            let storage = ConversationStorage(
                cloudSyncManager: manager,
                attachmentRepository: attachmentRepository,
                baseDirectory: baseDirectory
            )
            self.storage = storage
            self.syncCoordinator = syncCoordinator ?? ConversationSyncCoordinator(storage: storage)
        } else {
            self.storage = Self.liveStorage
            self.syncCoordinator = Self.liveSyncCoordinator
        }
    }

    // MARK: - Public

    func loadAll() async throws -> [Conversation] {
        try await loadAfterSynchronization { try await self.loadLocal() }
    }

    func loadBackupSnapshot() async throws -> ConversationBackupSnapshot {
        try await loadAfterSynchronization { try await self.storage.loadBackupSnapshot() }
    }

    private func loadAfterSynchronization<Value: Sendable>(
        _ load: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let requiredCloudIntent = settingsManager.getIsCloudSyncEnabled()
        guard requiredCloudIntent else { return try await load() }
        return try await mutationGate.perform {
            try await self.checkCloudIntent(requiredCloudIntent)
            _ = await self.syncCoordinator.synchronize()
            try await self.checkCloudIntent(requiredCloudIntent)
            return try await load()
        }
    }

    func loadLocal() async throws -> [Conversation] {
        let conversations = try await storage.loadLocal()
        updateWidgetSnapshot(conversations: conversations)
        return conversations
    }

    @discardableResult
    func save(
        _ conversation: Conversation,
        expectedBase: Conversation?,
        creationPlacement: ConversationCreationPlacement?
    ) async throws -> Conversation {
        try await performMutation { synchronize in
            try await saveSerialized(
                conversation,
                expectedBase: expectedBase,
                creationPlacement: creationPlacement,
                synchronize: synchronize
            )
        }
    }

    private func saveSerialized(
        _ conversation: Conversation,
        expectedBase: Conversation?,
        creationPlacement: ConversationCreationPlacement?,
        synchronize: Bool
    ) async throws -> Conversation {
        let admissionToken = await syncCoordinator.admissionToken()
        let saved = try await syncCoordinator.save(
            conversation,
            expectedBase: expectedBase,
            creationPlacement: creationPlacement,
            synchronize: synchronize,
            admissionToken: admissionToken
        )
        updateWidgetSnapshot(conversations: try await storage.loadLocal())
        return saved
    }

    func importBatch(
        _ conversations: [Conversation],
        organization: ConversationFolderSnapshot
    ) async throws -> [Conversation] {
        try await performMutation { synchronize in
            try await importBatchSerialized(conversations, organization: organization, synchronize: synchronize)
        }
    }

    private func importBatchSerialized(
        _ conversations: [Conversation],
        organization: ConversationFolderSnapshot,
        synchronize: Bool
    ) async throws -> [Conversation] {
        if synchronize {
            try requireSuccessfulSynchronization(await syncCoordinator.synchronize())
            try checkCloudIntent(true)
        }
        let saved = try await storage.importBatch(conversations, organization: organization)
        if synchronize {
            try requireSuccessfulSynchronization(await syncCoordinator.synchronize())
        }
        if !saved.isEmpty, let localConversations = try? await storage.loadLocal() {
            updateWidgetSnapshot(conversations: localConversations)
        }
        return saved
    }

    func setPinned(_ isPinned: Bool, conversationId: UUID) async throws -> Conversation? {
        try await performMutation { synchronize in
            try await setPinnedSerialized(isPinned, conversationId: conversationId, synchronize: synchronize)
        }
    }

    private func setPinnedSerialized(
        _ isPinned: Bool,
        conversationId: UUID,
        synchronize: Bool
    ) async throws -> Conversation? {
        let admissionToken = await syncCoordinator.admissionToken()
        let conversation = try await syncCoordinator.setPinned(
            isPinned,
            conversationId: conversationId,
            synchronize: synchronize,
            admissionToken: admissionToken
        )
        try await updateAfterMutation(conversation != nil)
        return conversation
    }

    func rename(_ conversationId: UUID, title: String) async throws -> Conversation? {
        try await performMutation { synchronize in
            try await renameSerialized(conversationId, title: title, synchronize: synchronize)
        }
    }

    private func renameSerialized(
        _ conversationId: UUID,
        title: String,
        synchronize: Bool
    ) async throws -> Conversation? {
        let admissionToken = await syncCoordinator.admissionToken()
        let conversation = try await syncCoordinator.rename(
            conversationId,
            title: title,
            synchronize: synchronize,
            admissionToken: admissionToken
        )
        try await updateAfterMutation(conversation != nil)
        return conversation
    }

    func updateTags(_ conversationId: UUID, tags: [ConversationTag]) async throws -> Conversation? {
        try await performMutation { synchronize in
            try await updateTagsSerialized(conversationId, tags: tags, synchronize: synchronize)
        }
    }

    private func updateTagsSerialized(
        _ conversationId: UUID,
        tags: [ConversationTag],
        synchronize: Bool
    ) async throws -> Conversation? {
        let admissionToken = await syncCoordinator.admissionToken()
        let conversation = try await syncCoordinator.updateTags(
            conversationId,
            tags: tags,
            synchronize: synchronize,
            admissionToken: admissionToken
        )
        try await updateAfterMutation(conversation != nil)
        return conversation
    }

    func delete(_ conversationId: UUID) async throws {
        try await performMutation { synchronize in
            try await deleteSerialized(conversationId, synchronize: synchronize)
        }
    }

    func deleteSynchronized(_ conversationId: UUID) async throws {
        guard settingsManager.getIsCloudSyncEnabled() else {
            throw CloudDataManagementError.cloudSyncDisabled
        }
        try await mutationGate.perform {
            try await self.checkCloudIntent(true)
            try await self.deleteSerialized(conversationId, synchronize: true)
        }
    }

    private func deleteSerialized(_ conversationId: UUID, synchronize: Bool) async throws {
        let admissionToken = await syncCoordinator.admissionToken()
        try await syncCoordinator.delete(
            conversationId,
            synchronize: synchronize,
            admissionToken: admissionToken
        )
        updateWidgetSnapshot(conversations: try await storage.loadLocal())
    }

    func deleteAll() async throws {
        try await performMutation { synchronize in
            try await deleteAllSerialized(synchronize: synchronize)
        }
    }

    private func deleteAllSerialized(synchronize: Bool) async throws {
        let admissionToken = await syncCoordinator.admissionToken()
        try await syncCoordinator.deleteAll(
            synchronize: synchronize,
            admissionToken: admissionToken
        )
        clearWidgetSnapshot()
    }

    @discardableResult
    func synchronize() async -> ConversationSyncResult {
        let requiredCloudIntent = settingsManager.getIsCloudSyncEnabled()
        guard requiredCloudIntent else { return .unavailable }
        do {
            return try await mutationGate.perform {
                try await self.checkCloudIntent(requiredCloudIntent)
                let result = await self.syncCoordinator.synchronize()
                try await self.checkCloudIntent(requiredCloudIntent)
                if let conversations = try? await self.storage.loadLocal() {
                    await self.updateWidgetSnapshot(conversations: conversations)
                }
                return result
            }
        } catch {
            return .unavailable
        }
    }

    func cancelSynchronization() async {
        await syncCoordinator.cancel()
    }

    func cancelSynchronizationAndDeleteAll() async throws {
        try await syncCoordinator.cancelAndDeleteAll()
        clearWidgetSnapshot()
    }

    func purgeLocalData(through marker: CloudPurgeMarker) async throws {
        await syncCoordinator.cancel()
        try await storage.purgeLocalData(through: marker)
        updateWidgetSnapshot(conversations: try await storage.loadLocal())
    }

    func validateLocalReset() async throws {
        try await storage.validateLocalReset()
    }
}

// MARK: - Folders

extension ConversationRepository {
    func loadFolderSnapshot() async throws -> ConversationFolderSnapshot {
        try await storage.loadFolderSnapshot()
    }

    func changeFolders(_ mutation: ConversationFolderMutation) async throws -> ConversationFolderSnapshot {
        let snapshot = try await performMutation { synchronize in
            try await self.storage.changeFolders(mutation, synchronize: synchronize)
        }
        NotificationCenter.default.post(name: .conversationDidUpdate, object: nil)
        return snapshot
    }
}

// MARK: - Private

private extension ConversationRepository {
    func checkCloudIntent(_ requiredCloudIntent: Bool) throws {
        try Task.checkCancellation()
        guard !requiredCloudIntent || settingsManager.getIsCloudSyncEnabled() else { throw CancellationError() }
    }

    func performMutation<Value: Sendable>(
        _ operation: @escaping @Sendable (Bool) async throws -> Value
    ) async throws -> Value {
        let requiredCloudIntent = settingsManager.getIsCloudSyncEnabled()
        guard requiredCloudIntent else { return try await operation(false) }
        return try await mutationGate.perform {
            try await self.checkCloudIntent(requiredCloudIntent)
            return try await operation(true)
        }
    }

    func requireSuccessfulSynchronization(_ result: ConversationSyncResult) throws {
        switch result {
        case .synchronized:
            return
        case .pendingDownload:
            throw ConversationSyncOperationError.pendingDownload
        case .unavailable:
            throw ConversationSyncOperationError.unavailable
        case .failed:
            throw CloudSyncError.cloudContentChanged
        }
    }

    func clearWidgetSnapshot() {
        guard AppGroupStore.clearConversations() else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: AppGroupStore.conversationsWidgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: AppGroupStore.pinnedConversationsWidgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: AppGroupStore.latestConversationWidgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: AppGroupStore.taggedConversationsWidgetKind)
    }

    func updateAfterMutation(_ didMutate: Bool) async throws {
        guard didMutate else { return }
        updateWidgetSnapshot(conversations: try await storage.loadLocal())
    }

    func updateWidgetSnapshot(conversations: [Conversation]) {
        let sorted = conversations.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        let recentConversations = makeWidgetConversations(from: Array(sorted.prefix(6)))
        let pinnedConversations = makeWidgetConversations(from: sorted.filter(\.isPinned))
        let tags = Array(Set(conversations.flatMap(\.tags).map(\.name))).sorted()
        let recentChanged = AppGroupStore.saveConversations(recentConversations)
        let pinnedChanged = AppGroupStore.savePinnedConversations(pinnedConversations)
        let tagsChanged = AppGroupStore.saveTags(tags)
        if recentChanged {
            WidgetCenter.shared.reloadTimelines(ofKind: AppGroupStore.conversationsWidgetKind)
            WidgetCenter.shared.reloadTimelines(ofKind: AppGroupStore.latestConversationWidgetKind)
        }
        if pinnedChanged {
            WidgetCenter.shared.reloadTimelines(ofKind: AppGroupStore.pinnedConversationsWidgetKind)
        }
        if tagsChanged || recentChanged || pinnedChanged {
            WidgetCenter.shared.reloadTimelines(ofKind: AppGroupStore.taggedConversationsWidgetKind)
        }
    }

    func makeWidgetConversations(from conversations: [Conversation]) -> [WidgetConversation] {
        conversations.map { conversation in
            WidgetConversation(
                id: conversation.id,
                title: conversation.title.isEmpty ? String(localized: "New Chat") : conversation.title,
                modelId: conversation.modelId,
                lastMessagePreview: conversation.messages.last?.content
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                updatedAt: conversation.updatedAt,
                isPinned: conversation.isPinned,
                tags: conversation.tags.map(\.name)
            )
        }
    }
}
