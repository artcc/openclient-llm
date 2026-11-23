//
//  ConversationStorage+Folders.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 23/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

extension ConversationStorage {
    func loadBackupSnapshot() throws -> (conversations: [Conversation], organization: ConversationFolderSnapshot) {
        (try loadLocal(), try readFolderState().snapshot)
    }

    func loadFolderSnapshot() throws -> ConversationFolderSnapshot {
        try ensureDirectoryExists()
        return try readFolderState().snapshot
    }

    func readFolderState() throws -> ConversationFolderState {
        let url = documentsURL.appendingPathComponent(ConversationFolderState.fileName)
        guard fileManager.fileExists(atPath: url.path) else { return ConversationFolderState() }
        let state = try makeDecoder().decode(ConversationFolderState.self, from: Data(contentsOf: url))
        try state.validate()
        return state
    }

    func writeFolderState(_ state: ConversationFolderState) throws {
        let url = documentsURL.appendingPathComponent(ConversationFolderState.fileName)
        if state == ConversationFolderState() {
            try removeLocalFileIfPresent(url)
            return
        }
        try state.validate()
        var sorted = state
        sorted.sort()
        let data = try makeEncoder().encode(sorted)
        try writeIfChanged(data, to: url)
        guard try Data(contentsOf: url) == data else { throw CloudSyncError.invalidConversationData }
    }

    func changeFolders(
        _ mutation: ConversationFolderMutation,
        synchronize: Bool
    ) throws -> ConversationFolderSnapshot {
        try Task.checkCancellation()
        try ensureDirectoryExists()
        if synchronize, cloudSyncManager.isCloudAvailable() {
            for attempt in 0..<2 {
                do {
                    let snapshot = try cloudSyncManager.loadConversationSyncSnapshot()
                    var plan = try makeSynchronizationPlan(snapshot: snapshot, conversationId: nil, mutation: nil)
                    try apply(
                        mutation, to: &plan.output.folderState,
                        conversationIDs: Set(plan.output.conversations.map(\.id)),
                        barrier: plan.output.deleteAllMarker?.deletedAt
                    )
                    try commitSynchronization(plan: plan, snapshot: snapshot)
                    return try readFolderState().snapshot
                } catch CloudSyncError.cloudContentChanged where attempt == 0 {
                    continue
                } catch CloudSyncError.requiredDownloadPending {
                    break
                } catch CloudSyncError.containerUnavailable {
                    break
                }
            }
        }
        let conversationIDs: Set<UUID>
        if case .move(let ids, _) = mutation {
            let pending = try loadPendingDeletionIds()
            let tombstones = try loadTombstones()
            let marker = try loadDeleteAllMarker()
            conversationIDs = try Set(ids.filter { id in
                guard !pending.contains(id), let chat = try loadLocalConversation(id: id) else { return false }
                return shouldKeep(chat, tombstones: tombstones, marker: marker)
            })
        } else {
            conversationIDs = []
        }
        var state = try readFolderState()
        let barrier = try newestMarker(loadDeleteAllMarker(), loadLocalResetMarker())?.deletedAt
        try apply(mutation, to: &state, conversationIDs: conversationIDs, barrier: barrier)
        try writeFolderState(state)
        return try readFolderState().snapshot
    }

    func importFolderState(_ organization: ConversationFolderSnapshot, conversationIDs: Set<UUID>) throws {
        guard !organization.folders.isEmpty || !organization.memberships.isEmpty else { return }
        var state = try readFolderState()
        let ids = Set(organization.folders.map(\.id))
        let assigned = Set(organization.memberships.map(\.conversationId))
        guard ids.isDisjoint(with: state.folders.map(\.id)),
              ids.isDisjoint(with: state.tombstones.map(\.id)),
              assigned.isDisjoint(with: state.memberships.map(\.conversationId)),
              organization.memberships.allSatisfy({
                  conversationIDs.contains($0.conversationId) && ($0.folderId.map(ids.contains) ?? true)
              }) else { throw CloudSyncError.invalidConversationData }
        state.folders += organization.folders
        state.memberships += organization.memberships
        try writeFolderState(state)
    }

    func applyCreationPlacement(
        _ placement: ConversationCreationPlacement?,
        to conversationID: UUID,
        cloud: ConversationCloudSyncSnapshot?
    ) throws {
        guard let placement else { return }
        var state = try readFolderState()
        let marker = try newestMarker(loadDeleteAllMarker(), cloud?.deleteAllMarker)
        let source: ConversationFolderState
        if let cloud {
            let tombstones = try reconciliationTombstones(snapshot: cloud, pendingDeletionIds: loadPendingDeletionIds())
            var parents: [UUID] = []
            if case .inheritFrom(let id) = placement {
                let versions = try [loadLocalConversation(id: id), cloud.conversations[id]].compactMap { $0 }
                if versions.contains(where: { shouldKeep($0, tombstones: tombstones, marker: marker) }) {
                    parents.append(id)
                }
            }
            source = try reconcileFolders(cloud: cloud, conversations: parents,
                                          conversationTombstones: tombstones, barrier: marker?.deletedAt)
        } else {
            source = state
        }
        let folderID: UUID?
        switch placement {
        case .folder(let id):
            folderID = source.folders.contains { $0.id == id } ? id : nil
        case .inheritFrom(let id):
            folderID = source.snapshot.folderID(for: id)
        }
        guard let folderID else { return }
        let barrier = try newestMarker(loadLocalResetMarker(), marker)?.deletedAt
        state.memberships.removeAll { $0.conversationId == conversationID }
        state.memberships.append(.init(
            conversationId: conversationID, folderId: folderID, updatedAt: folderRevision(after: barrier)
        ))
        state.pendingCreationPlacements = (state.pendingCreationPlacements ?? []) + [conversationID]
        try writeFolderState(state)
    }
}

private extension ConversationStorage {
    func folderRevision(after barrier: Date?) -> Date {
        // The formatted date must remain strictly newer after the storage codec's round trip.
        max(Date(), (barrier ?? .distantPast).addingTimeInterval(0.001))
    }

    func apply(
        _ mutation: ConversationFolderMutation,
        to state: inout ConversationFolderState,
        conversationIDs: Set<UUID>,
        barrier: Date?
    ) throws {
        switch mutation {
        case let .create(id, name), let .rename(id, name):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !state.tombstones.contains(where: { $0.id == id }) else {
                throw CloudSyncError.invalidConversationData
            }
            let existing = state.folders.first { $0.id == id }
            if case .rename = mutation, existing == nil { throw CloudSyncError.staleConversationRevision }
            guard existing?.name != trimmed else { return }
            state.folders.removeAll { $0.id == id }
            let date = folderRevision(after: [barrier, existing?.updatedAt].compactMap { $0 }.max())
            state.folders.append(ConversationFolder(id: id, name: trimmed, updatedAt: date))
        case .delete(let id):
            guard let folder = state.folders.first(where: { $0.id == id }) else { return }
            let date = folderRevision(after: max(barrier ?? .distantPast, folder.updatedAt))
            state.tombstones.removeAll { $0.id == id }
            state.tombstones.append(CloudDeletionMarker(id: id, deletedAt: date))
            state.folders.removeAll { $0.id == id }
        case let .move(ids, folderID):
            guard ids.isSubset(of: conversationIDs),
                  folderID.map({ id in state.folders.contains { $0.id == id } }) ?? true else {
                throw CloudSyncError.staleConversationRevision
            }
            let selected = state.memberships.filter { ids.contains($0.conversationId) }
            let existing = Dictionary(uniqueKeysWithValues: selected.map { ($0.conversationId, $0) })
            let pending = Set(state.pendingCreationPlacements ?? [])
            let changed = ids.filter { id in
                existing[id] == nil || existing[id]?.folderId != folderID || pending.contains(id)
            }
            state.pendingCreationPlacements?.removeAll { ids.contains($0) }
            if state.pendingCreationPlacements?.isEmpty == true { state.pendingCreationPlacements = nil }
            state.memberships.removeAll { changed.contains($0.conversationId) }
            for id in changed {
                let previous = existing[id]?.updatedAt
                let date = folderRevision(after: [barrier, previous].compactMap { $0 }.max())
                state.memberships.append(.init(conversationId: id, folderId: folderID, updatedAt: date))
            }
        }
        state.sort()
    }
}
