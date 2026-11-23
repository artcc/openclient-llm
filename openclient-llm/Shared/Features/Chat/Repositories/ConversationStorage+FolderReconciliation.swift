//
//  ConversationStorage+FolderReconciliation.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 23/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

extension ConversationStorage {
    func reconcileFolders(
        cloud: ConversationCloudSyncSnapshot,
        conversations: [UUID],
        conversationTombstones: [ConversationTombstone],
        barrier: Date?
    ) throws -> ConversationFolderState {
        var local = try readFolderState()
        var remote = cloud.folderState
        if let barrier {
            local.purge(through: barrier)
            remote.purge(through: barrier)
        }
        let markers = Dictionary((local.tombstones + remote.tombstones).map { ($0.id, $0) }) {
            $0.deletedAt >= $1.deletedAt ? $0 : $1
        }
        let folders = try mergeFolderRecords(
            (local.folders + remote.folders).filter { markers[$0.id] == nil },
            id: \.id, date: \.updatedAt, recovery: ConversationFolderState.foldersDirectory
        )
        let liveIDs = Set(conversations)
        let deleted = Dictionary(
            conversationTombstones.map { ($0.conversationId, $0.deletedAt) }, uniquingKeysWith: max
        )
        func keepMembership(_ membership: ConversationFolderMembership) -> Bool {
            guard let date = deleted[membership.conversationId] else { return true }
            return liveIDs.contains(membership.conversationId) && membership.updatedAt > date
        }
        let remoteMemberships = remote.memberships.filter(keepMembership)
        if let pending = local.pendingCreationPlacements {
            let assigned = Set(remoteMemberships.map(\.conversationId))
            let superseded = Set(pending.filter { id in
                if assigned.contains(id) { return true }
                guard let chat = cloud.conversations[id] else { return false }
                return (deleted[id].map { chat.updatedAt > $0 } ?? true)
                    && (barrier.map { chat.updatedAt > $0 } ?? true)
            })
            local.memberships.removeAll { superseded.contains($0.conversationId) }
        }
        let memberships = try mergeFolderRecords(
            local.memberships.filter(keepMembership) + remoteMemberships,
            id: \.conversationId, date: \.updatedAt, recovery: ConversationFolderState.membershipsDirectory
        )
        var result = ConversationFolderState(
            folders: folders, memberships: memberships, tombstones: Array(markers.values)
        )
        result.sort()
        return result
    }

    func manageFolderRecovery(purgeThrough barrier: Date? = nil) throws {
        try manageFolderRecovery(
            ConversationFolder.self, date: \.updatedAt,
            directory: ConversationFolderState.foldersDirectory, barrier: barrier
        )
        try manageFolderRecovery(
            ConversationFolderMembership.self, date: \.updatedAt,
            directory: ConversationFolderState.membershipsDirectory, barrier: barrier
        )
    }
}

private extension ConversationStorage {
    func mergeFolderRecords<Record: Codable & Equatable>(
        _ records: [Record],
        id: KeyPath<Record, UUID>,
        date: KeyPath<Record, Date>,
        recovery: String
    ) throws -> [Record] {
        var result: [UUID: Record] = [:]
        for record in records {
            let identifier = record[keyPath: id]
            guard let existing = result[identifier] else {
                result[identifier] = record
                continue
            }
            guard existing != record else { continue }
            if record[keyPath: date] != existing[keyPath: date] {
                if record[keyPath: date] > existing[keyPath: date] { result[identifier] = record }
                continue
            }
            let existingData = try makeEncoder().encode(existing)
            let recordData = try makeEncoder().encode(record)
            let wins = existingData.lexicographicallyPrecedes(recordData)
            let loser = wins ? existingData : recordData
            let directory = recoveryDirectoryURL.appendingPathComponent(recovery, isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("\(identifier.uuidString)-\(recoveryDigest(for: loser)).json")
            try writeIfChanged(loser, to: url)
            guard try Data(contentsOf: url) == loser else { throw CloudSyncError.invalidConversationData }
            if wins { result[identifier] = record }
        }
        return Array(result.values)
    }

    func manageFolderRecovery<Record: Decodable>(
        _ type: Record.Type,
        date: KeyPath<Record, Date>,
        directory: String,
        barrier: Date?
    ) throws {
        let root = recoveryDirectoryURL.appendingPathComponent(directory, isDirectory: true)
        guard fileManager.fileExists(atPath: root.path) else { return }
        for url in try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            where url.pathExtension == "json" {
            let record = try makeDecoder().decode(type, from: Data(contentsOf: url))
            if let barrier, record[keyPath: date] <= barrier { try fileManager.removeItem(at: url) }
        }
    }
}
