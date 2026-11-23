//
//  ConversationStorage+DataManagement.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 11/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

// MARK: - Data Management

extension ConversationStorage {
    func validateLocalReset() throws {
        try ensureDirectoryExists()
        _ = try loadLocalConversationFiles()
        _ = try loadTombstones()
        _ = try loadDeleteAllMarker()
        _ = try loadLocalAttachmentFiles()
        _ = try readFolderState()
        try manageFolderRecovery()
        try validateRecoveryConversations()
    }

    func purgeLocalData(through marker: CloudPurgeMarker) throws {
        try Task.checkCancellation()
        try ensureDirectoryExists()
        let plan = try makeLocalPurgePlan(through: marker)
        try applyLocalPurge(plan, through: marker)
        try manageFolderRecovery(purgeThrough: marker.deletedAt)
        try purgeRecoveryData(through: marker, retaining: plan.survivingConversationIds)
    }
}

// MARK: - Private

private extension ConversationStorage {
    struct LocalPurgePlan {
        let staleConversationIds: [UUID]
        let stalePendingMutationIds: [UUID]
        let stalePendingDeletionIds: [UUID]
        let survivingConversationIds: Set<UUID>
    }

    func makeLocalPurgePlan(through marker: CloudPurgeMarker) throws -> LocalPurgePlan {
        let conversations = try loadLocalConversations()
        let conversationsById = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0) })
        let pendingMutationBases = try loadPendingMutationBases()
        let pendingDeletionIds = try loadPendingDeletionIds()
        let staleConversationIds = Set(conversations.filter { $0.updatedAt <= marker.deletedAt }.map(\.id))
        let stalePendingMutationIds = Set(pendingMutationBases.values
            .filter { $0.updatedAt <= marker.deletedAt }
            .map(\.id))
        let stalePendingDeletionIds = Set(pendingDeletionIds.filter { id in
            let baseRevision = conversationsById[id]?.updatedAt ?? pendingMutationBases[id]?.updatedAt
            return baseRevision.map { $0 <= marker.deletedAt } ?? true
        })
        return LocalPurgePlan(
            staleConversationIds: sortedIds(staleConversationIds),
            stalePendingMutationIds: sortedIds(stalePendingMutationIds),
            stalePendingDeletionIds: sortedIds(stalePendingDeletionIds),
            survivingConversationIds: Set(conversations.map(\.id)).subtracting(staleConversationIds)
        )
    }

    func applyLocalPurge(_ plan: LocalPurgePlan, through marker: CloudPurgeMarker) throws {
        let transaction = try ConversationLocalTransaction(
            fileManager: fileManager,
            documentsURL: documentsURL,
            backsUpAllAttachments: true
        )
        do {
            var state = try readFolderState()
            state.purge(through: marker.deletedAt)
            let removed = Set(plan.staleConversationIds)
            state.memberships.removeAll { removed.contains($0.conversationId) }
            state.discardUnassignedCreationPlacements()
            try writeFolderState(state)
            try removeStaleLocalData(plan)
            let attachmentsURL = documentsURL.appendingPathComponent("Attachments", isDirectory: true)
            try purgeAttachmentFolders(at: attachmentsURL, retaining: plan.survivingConversationIds)
            try transaction.commit()
        } catch {
            try transaction.rollback()
            throw error
        }
    }

    func removeStaleLocalData(_ plan: LocalPurgePlan) throws {
        for id in plan.staleConversationIds {
            try removeLocalFileIfPresent(conversationFileURL(for: id))
        }
        for id in plan.stalePendingMutationIds {
            try removePendingMutation(conversationId: id)
        }
        for id in plan.stalePendingDeletionIds {
            try removePendingDeletion(conversationId: id)
        }
    }

    func purgeRecoveryData(through marker: CloudPurgeMarker, retaining ids: Set<UUID>) throws {
        guard fileManager.fileExists(atPath: recoveryDirectoryURL.path) else { return }
        let urls = try sortedContents(of: recoveryDirectoryURL)
        for url in urls {
            if url.lastPathComponent == "Attachments" {
                try purgeAttachmentFolders(at: url, retaining: ids)
            } else if url.pathExtension == "json" {
                try purgeRecoveryConversation(at: url, through: marker)
            }
        }
    }

    func purgeRecoveryConversation(at url: URL, through marker: CloudPurgeMarker) throws {
        let conversation = try makeDecoder().decode(Conversation.self, from: Data(contentsOf: url))
        guard conversation.updatedAt <= marker.deletedAt else { return }
        try fileManager.removeItem(at: url)
    }

    func purgeAttachmentFolders(at directory: URL, retaining ids: Set<UUID>) throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        for folder in try sortedContents(of: directory) {
            let id = UUID(uuidString: folder.lastPathComponent)
            guard id.map({ !ids.contains($0) }) ?? true else { continue }
            try fileManager.removeItem(at: folder)
        }
    }

    func validateRecoveryConversations() throws {
        guard fileManager.fileExists(atPath: recoveryDirectoryURL.path) else { return }
        for url in try sortedContents(of: recoveryDirectoryURL) where url.pathExtension == "json" {
            _ = try makeDecoder().decode(Conversation.self, from: Data(contentsOf: url))
        }
    }

    func sortedContents(of directory: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func sortedIds(_ ids: Set<UUID>) -> [UUID] {
        ids.sorted { $0.uuidString < $1.uuidString }
    }
}
