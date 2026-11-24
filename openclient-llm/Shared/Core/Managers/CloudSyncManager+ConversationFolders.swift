//
//  CloudSyncManager+ConversationFolders.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 23/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

extension CloudSyncManager {
    func validateFolderTransition(
        _ output: ConversationCloudSyncOutput,
        from snapshot: ConversationCloudSyncSnapshot
    ) throws {
        let state = output.folderState
        try state.validate()
        let barrier = [output.deleteAllMarker?.deletedAt, snapshot.deleteAllMarker?.deletedAt].compactMap { $0 }.max()
        let survivingFolders = Set(state.folders.map(\.id))
        let deletedFolders = Set(state.tombstones.map(\.id))
        let memberships = Set(state.memberships.map(\.conversationId))
        let deletedChats = Set(output.tombstones.map(\.conversationId))
        func isPurged(_ date: Date) -> Bool { barrier.map { date <= $0 } ?? false }
        guard survivingFolders.isDisjoint(with: deletedFolders),
              !state.folders.contains(where: { isPurged($0.updatedAt) }),
              !state.memberships.contains(where: { isPurged($0.updatedAt) }),
              snapshot.folderState.folders.allSatisfy({
                  survivingFolders.contains($0.id) || deletedFolders.contains($0.id) || isPurged($0.updatedAt)
              }),
              snapshot.folderState.memberships.allSatisfy({
                  memberships.contains($0.conversationId)
                    || deletedChats.contains($0.conversationId) || isPurged($0.updatedAt)
              }),
              snapshot.folderState.tombstones.allSatisfy({ deletedFolders.contains($0.id) })
        else { throw CloudSyncError.invalidConversationData }
    }

    func loadConversationFolderState(in documentsURL: URL) throws -> ConversationFolderState {
        var state = try ConversationFolderState(
            folders: readFolderRecords(in: documentsURL, directory: ConversationFolderState.foldersDirectory, id: \.id),
            memberships: readFolderRecords(
                in: documentsURL, directory: ConversationFolderState.membershipsDirectory, id: \.conversationId
            ),
            tombstones: readFolderRecords(
                in: documentsURL, directory: ConversationFolderState.tombstonesDirectory, id: \.id
            )
        )
        try state.validate()
        state.sort()
        return state
    }

    func writeConversationFolderState(
        _ state: ConversationFolderState,
        replacing previous: ConversationFolderState,
        in documentsURL: URL,
        checkSession: () throws -> Void
    ) throws {
        try state.validate()
        try writeFolderRecords(
            state.tombstones, replacing: previous.tombstones,
            directory: documentsURL.appendingPathComponent(ConversationFolderState.tombstonesDirectory),
            id: \.id, checkSession: checkSession
        )
        try writeFolderRecords(
            state.folders, replacing: previous.folders,
            directory: documentsURL.appendingPathComponent(ConversationFolderState.foldersDirectory),
            id: \.id, checkSession: checkSession
        )
        try writeFolderRecords(
            state.memberships, replacing: previous.memberships,
            directory: documentsURL.appendingPathComponent(ConversationFolderState.membershipsDirectory),
            id: \.conversationId, checkSession: checkSession
        )
    }
}

private extension CloudSyncManager {
    func readFolderRecords<Record: Decodable>(
        in documentsURL: URL,
        directory: String,
        id: KeyPath<Record, UUID>
    ) throws -> [Record] {
        let root = documentsURL.appendingPathComponent(directory, isDirectory: true)
        try requireDownloadedFile(at: root)
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw CloudSyncError.invalidConversationData
        }
        return try categoryContents(of: root).filter { $0.pathExtension == "json" }.map { url in
            let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else {
                throw CloudSyncError.invalidConversationData
            }
            let record = try SyncJSONCoding.makeDecoder().decode(Record.self, from: Data(contentsOf: url))
            guard url.lastPathComponent == "\(record[keyPath: id].uuidString).json" else {
                throw CloudSyncError.invalidConversationData
            }
            return record
        }
    }

    func writeFolderRecords<Record: Codable & Equatable>(
        _ records: [Record],
        replacing previous: [Record],
        directory: URL,
        id: KeyPath<Record, UUID>,
        checkSession: () throws -> Void
    ) throws {
        let existing = Dictionary(uniqueKeysWithValues: previous.map { ($0[keyPath: id], $0) })
        let kept = Set(records.map { $0[keyPath: id] })
        for record in records where existing[record[keyPath: id]] != record {
            try Task.checkCancellation()
            try checkSession()
            let url = directory.appendingPathComponent("\(record[keyPath: id].uuidString).json")
            try writeMemoryValue(record, to: url)
        }
        for removed in Set(existing.keys).subtracting(kept) {
            try Task.checkCancellation()
            try checkSession()
            try removeCategoryItemIfPresent(at: directory.appendingPathComponent("\(removed.uuidString).json"))
        }
    }
}
