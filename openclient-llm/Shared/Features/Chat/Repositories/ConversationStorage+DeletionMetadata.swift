//
//  ConversationStorage+DeletionMetadata.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 10/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

// MARK: - Deletion Metadata

extension ConversationStorage {
    func loadTombstones() throws -> [ConversationTombstone] {
        guard fileManager.fileExists(atPath: tombstonesURL.path) else { return [] }
        let data = try Data(contentsOf: tombstonesURL)
        return try SyncJSONCoding.makeDecoder().decode([ConversationTombstone].self, from: data)
    }

    func saveTombstones(_ tombstones: [ConversationTombstone]) throws {
        try writeDeletionDataIfChanged(SyncJSONCoding.makeEncoder().encode(tombstones), to: tombstonesURL)
    }

    func loadDeleteAllMarker() throws -> ConversationDeleteAllMarker? {
        guard fileManager.fileExists(atPath: deleteAllMarkerURL.path) else { return nil }
        let data = try Data(contentsOf: deleteAllMarkerURL)
        return try SyncJSONCoding.makeDecoder().decode(ConversationDeleteAllMarker.self, from: data)
    }

    func saveDeleteAllMarker(_ marker: ConversationDeleteAllMarker) throws {
        try writeDeletionDataIfChanged(SyncJSONCoding.makeEncoder().encode(marker), to: deleteAllMarkerURL)
    }

    func loadLocalResetMarker() throws -> ConversationDeleteAllMarker? {
        guard fileManager.fileExists(atPath: localResetMarkerURL.path) else { return nil }
        let data = try Data(contentsOf: localResetMarkerURL)
        return try SyncJSONCoding.makeDecoder().decode(ConversationDeleteAllMarker.self, from: data)
    }

    func saveLocalResetMarker(_ marker: ConversationDeleteAllMarker) throws {
        try writeDeletionDataIfChanged(SyncJSONCoding.makeEncoder().encode(marker), to: localResetMarkerURL)
    }

    func newestMarker(
        _ local: ConversationDeleteAllMarker?,
        _ cloud: ConversationDeleteAllMarker?
    ) -> ConversationDeleteAllMarker? {
        [local, cloud].compactMap { $0 }.max { $0.deletedAt < $1.deletedAt }
    }

    func mergedTombstones(_ adding: [ConversationTombstone]) throws -> [ConversationTombstone] {
        try mergeTombstones(loadTombstones() + adding)
    }

    func mergeTombstones(_ tombstones: [ConversationTombstone]) -> [ConversationTombstone] {
        var latest: [UUID: ConversationTombstone] = [:]
        for tombstone in tombstones {
            let existingDate = latest[tombstone.conversationId]?.deletedAt ?? .distantPast
            if existingDate < tombstone.deletedAt {
                latest[tombstone.conversationId] = tombstone
            }
        }
        return latest.values.sorted {
            $0.conversationId.uuidString < $1.conversationId.uuidString
        }
    }
}

// MARK: - Private

extension ConversationStorage {
    private func writeDeletionDataIfChanged(_ data: Data, to url: URL) throws {
        if (try? Data(contentsOf: url)) != data {
            try data.write(to: url, options: .atomic)
        }
        guard try Data(contentsOf: url) == data else {
            throw CloudSyncError.invalidConversationData
        }
    }

    func applyLocalDelete(_ conversationId: UUID) throws {
        let conversationDate = try loadLocalConversation(id: conversationId)?.updatedAt
        let existingTombstoneDate = try loadTombstones()
            .first(where: { $0.conversationId == conversationId })?.deletedAt
        let hasNewerConversation = conversationDate.map { $0 > existingTombstoneDate ?? .distantPast } == true
        if existingTombstoneDate == nil || hasNewerConversation {
            let barrier = [conversationDate, existingTombstoneDate].compactMap { $0 }.max()
            let tombstone = ConversationTombstone(
                conversationId: conversationId,
                deletedAt: nextModificationDate(after: barrier)
            )
            try saveTombstones(try mergedTombstones([tombstone]))
        }
        var state = try readFolderState()
        state.memberships.removeAll { $0.conversationId == conversationId }
        state.discardUnassignedCreationPlacements()
        try writeFolderState(state)
        try removeLocalFileIfPresent(conversationFileURL(for: conversationId))
        try removePendingMutation(conversationId: conversationId)
        try removePendingDeletion(conversationId: conversationId)
        try attachmentRepository.deleteAll(forConversationId: conversationId)
    }

    func delete(
        _ conversationId: UUID,
        using snapshot: ConversationCloudSyncSnapshot
    ) throws {
        try Task.checkCancellation()
        try ensureDirectoryExists()
        try savePendingDeletion(conversationId: conversationId)
        try synchronize(with: snapshot)
        try removeRecoveryData(conversationId: conversationId)
    }

    func deleteAll(using snapshot: ConversationCloudSyncSnapshot) throws {
        try Task.checkCancellation()
        try ensureDirectoryExists()
        let marker = try deletionMarker(snapshot: snapshot)
        let plan = try makeSynchronizationPlan(
            snapshot: snapshot,
            conversationId: nil,
            deleteAllMarkerOverride: marker,
            mutation: nil
        )
        try Task.checkCancellation()
        try commitSynchronization(plan: plan, snapshot: snapshot)
        if fileManager.fileExists(atPath: recoveryDirectoryURL.path) {
            try fileManager.removeItem(at: recoveryDirectoryURL)
        }
        try ensureDirectoryExists()
    }

    func applyLocalDeleteAll(createCloudMarker: Bool) throws {
        if createCloudMarker {
            let newestConversationDate = try loadLocalConversations().map(\.updatedAt).max()
            let existingMarkerDate = try loadDeleteAllMarker()?.deletedAt
            let hasNewerConversation = newestConversationDate.map {
                $0 > existingMarkerDate ?? .distantPast
            } == true
            if existingMarkerDate == nil || hasNewerConversation {
                let barrier = [newestConversationDate, existingMarkerDate].compactMap { $0 }.max()
                try saveDeleteAllMarker(
                    ConversationDeleteAllMarker(deletedAt: nextModificationDate(after: barrier))
                )
            }
        } else {
            let newestConversationDate = try loadLocalConversations().map(\.updatedAt).max()
            let existingResetDate = try loadLocalResetMarker()?.deletedAt
            try saveLocalResetMarker(ConversationDeleteAllMarker(
                deletedAt: nextModificationDate(after: [
                    newestConversationDate,
                    existingResetDate
                ].compactMap { $0 }.max())
            ))
            try removeLocalFileIfPresent(tombstonesURL)
            try removeLocalFileIfPresent(deleteAllMarkerURL)
        }
        try removeAllPendingMutations()
        try removeAllPendingDeletions()
        try removeLocalFileIfPresent(documentsURL.appendingPathComponent(ConversationFolderState.fileName))
        try removeLocalFileIfPresent(directoryURL)
        try attachmentRepository.deleteAll()
    }

    func deletionTombstone(
        for conversationId: UUID,
        snapshot: ConversationCloudSyncSnapshot
    ) throws -> ConversationTombstone {
        let existingTombstone = mergeTombstones(try loadTombstones() + snapshot.tombstones)
            .first { $0.conversationId == conversationId }
        let newestRevision = [
            try loadLocalConversation(id: conversationId)?.updatedAt,
            snapshot.conversations[conversationId]?.updatedAt
        ].compactMap { $0 }.max()
        if let existingTombstone,
           newestRevision.map({ $0 < existingTombstone.deletedAt }) ?? true {
            return existingTombstone
        }
        let barrier = [
            newestRevision,
            existingTombstone?.deletedAt,
            try loadDeleteAllMarker()?.deletedAt,
            snapshot.deleteAllMarker?.deletedAt
        ].compactMap { $0 }.max()
        return ConversationTombstone(
            conversationId: conversationId,
            deletedAt: nextModificationDate(after: barrier)
        )
    }

    private func deletionMarker(
        snapshot: ConversationCloudSyncSnapshot
    ) throws -> ConversationDeleteAllMarker {
        let existingMarker = newestMarker(try loadDeleteAllMarker(), snapshot.deleteAllMarker)
        let chatRevisions = try loadLocalConversations().map(\.updatedAt)
            + snapshot.conversations.values.map(\.updatedAt)
        let folderRevisions = try readFolderState().revisions + snapshot.folderState.revisions
        let newestRevision = (chatRevisions + folderRevisions).max()
        if let existingMarker,
           newestRevision.map({ $0 < existingMarker.deletedAt }) ?? true {
            return existingMarker
        }
        return ConversationDeleteAllMarker(deletedAt: nextModificationDate(after: [
            newestRevision,
            existingMarker?.deletedAt
        ].compactMap { $0 }.max()))
    }

    func removeRecoveryData(conversationId: UUID) throws {
        guard fileManager.fileExists(atPath: recoveryDirectoryURL.path) else { return }
        let urls = try fileManager.contentsOfDirectory(at: recoveryDirectoryURL, includingPropertiesForKeys: nil)
        for url in urls where url.lastPathComponent.hasPrefix(conversationId.uuidString) {
            try fileManager.removeItem(at: url)
        }
        let attachmentURL = recoveryDirectoryURL
            .appendingPathComponent("Attachments", isDirectory: true)
            .appendingPathComponent(conversationId.uuidString, isDirectory: true)
        try removeLocalFileIfPresent(attachmentURL)
    }

    func removeLocalFileIfPresent(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}
