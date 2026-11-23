//
//  ConversationFolderState.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 23/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

nonisolated struct ConversationFolderState: Codable, Equatable, Sendable {
    static let fileName = "ConversationFolderState.json"
    static let foldersDirectory = "ConversationFolders"
    static let membershipsDirectory = "ConversationFolderMemberships"
    static let tombstonesDirectory = "ConversationFolderTombstones"

    var folders: [ConversationFolder] = []
    var memberships: [ConversationFolderMembership] = []
    var tombstones: [CloudDeletionMarker] = []
    // Local only: an initial placement must not overwrite a chat that turns out to exist in iCloud.
    var pendingCreationPlacements: [UUID]?

    var revisions: [Date] {
        folders.map(\.updatedAt) + memberships.map(\.updatedAt) + tombstones.map(\.deletedAt)
    }

    var snapshot: ConversationFolderSnapshot {
        ConversationFolderSnapshot(folders: folders, memberships: memberships)
    }

    func validate() throws {
        let validNames = folders.allSatisfy {
            !$0.name.isEmpty && $0.name == $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let assigned = Set(memberships.map(\.conversationId))
        let pending = pendingCreationPlacements ?? []
        guard Set(folders.map(\.id)).count == folders.count,
              assigned.count == memberships.count,
              pending.count == Set(pending).count, Set(pending).isSubset(of: assigned),
              Set(tombstones.map(\.id)).count == tombstones.count,
              validNames else { throw CloudSyncError.invalidConversationData }
    }

    mutating func sort() {
        folders.sort { $0.id.uuidString < $1.id.uuidString }
        memberships.sort { $0.conversationId.uuidString < $1.conversationId.uuidString }
        tombstones.sort { $0.id.uuidString < $1.id.uuidString }
        pendingCreationPlacements?.sort { $0.uuidString < $1.uuidString }
    }

    mutating func purge(through date: Date) {
        folders.removeAll { $0.updatedAt <= date }
        memberships.removeAll { $0.updatedAt <= date }
        discardUnassignedCreationPlacements()
    }

    mutating func discardUnassignedCreationPlacements() {
        guard pendingCreationPlacements != nil else { return }
        let assigned = Set(memberships.map(\.conversationId))
        pendingCreationPlacements?.removeAll { !assigned.contains($0) }
        if pendingCreationPlacements?.isEmpty == true { pendingCreationPlacements = nil }
    }
}
