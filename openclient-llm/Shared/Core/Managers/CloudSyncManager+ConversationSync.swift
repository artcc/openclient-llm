//
//  CloudSyncManager+ConversationSync.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 10/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

extension CloudSyncManager {
    func loadConversationSyncSnapshot() throws -> ConversationCloudSyncSnapshot {
        let session = try makeSyncSession()
        guard containerProvider.isMetadataReady(for: session) else {
            throw CloudSyncError.requiredDownloadPending
        }
        return try fileCoordinator.read(at: session.containerURL) { containerURL in
            try validate(session)
            return try makeConversationSnapshot(session: session, containerURL: containerURL)
        }
    }

    func validateConversationSyncOutput(
        _ output: ConversationCloudSyncOutput,
        basedOn snapshot: ConversationCloudSyncSnapshot
    ) throws {
        try validate(snapshot.session)
        try fileCoordinator.read(at: snapshot.session.containerURL) { containerURL in
            try validate(snapshot.session)
            let current = try makeConversationSnapshot(
                session: snapshot.session,
                containerURL: containerURL
            )
            try validateUnchanged(current, comparedTo: snapshot, output: output)
            try validateOutput(output)
            try validate(snapshot.session)
        }
    }

    func applyConversationSyncOutput(
        _ output: ConversationCloudSyncOutput,
        basedOn snapshot: ConversationCloudSyncSnapshot
    ) throws {
        try validate(snapshot.session)
        try fileCoordinator.write(at: snapshot.session.containerURL, options: []) { containerURL in
            try validate(snapshot.session)
            let current = try makeConversationSnapshot(
                session: snapshot.session,
                containerURL: containerURL
            )
            try validateUnchanged(current, comparedTo: snapshot, output: output)
            try apply(output, snapshot: snapshot, containerURL: containerURL)
        }
    }
}

// MARK: - Snapshot

private extension CloudSyncManager {
    func makeSyncSession() throws -> CloudSyncSession {
        guard let session = containerProvider.currentSession() else {
            throw CloudSyncError.containerUnavailable
        }
        return session
    }

    func validate(_ session: CloudSyncSession) throws {
        guard let currentSession = containerProvider.currentSession() else {
            throw CloudSyncError.containerUnavailable
        }
        guard currentSession == session else {
            throw CloudSyncError.containerIdentityChanged
        }
        guard containerProvider.isMetadataReady(for: session) else {
            throw CloudSyncError.requiredDownloadPending
        }
    }

    func makeConversationSnapshot(
        session: CloudSyncSession,
        containerURL: URL
    ) throws -> ConversationCloudSyncSnapshot {
        let documentsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
        let manifestURL = documentsURL.appendingPathComponent("SyncManifest.json")
        try requireDownloadedFile(at: manifestURL)
        let manifestData = try dataIfPresent(at: manifestURL)
        _ = try CloudSyncManifest.decode(manifestData)

        let conversationResult = try loadConversations(in: documentsURL)
        let tombstoneResult = try loadTombstones(in: documentsURL)
        let markerResult = try loadDeleteAllMarker(in: documentsURL)
        let purgeMarker = try readPurgeMarker(in: documentsURL)
        let tombstoneDates = Dictionary(grouping: tombstoneResult.values, by: \.conversationId).mapValues { values in
            values.map(\.deletedAt).max() ?? .distantPast
        }
        let effectiveMarkerDate = [markerResult.value?.deletedAt, purgeMarker?.deletedAt]
            .compactMap { $0 }
            .max()
        let eligibleConversations = conversationResult.values.filter { _, conversation in
            let barriers = [effectiveMarkerDate, tombstoneDates[conversation.id]].compactMap { $0 }
            guard let barrier = barriers.max() else { return true }
            return conversation.updatedAt > barrier
        }
        let eligibleIDs = Set(eligibleConversations.keys)
        let attachmentResult = try loadAttachments(
            in: documentsURL,
            conversations: eligibleConversations
        )

        return ConversationCloudSyncSnapshot(
            session: session,
            manifestData: manifestData,
            conversations: eligibleConversations,
            conversationData: conversationResult.data.filter { eligibleIDs.contains($0.key) },
            tombstones: tombstoneResult.values,
            tombstoneData: tombstoneResult.data,
            legacyTombstoneData: tombstoneResult.legacyData,
            deleteAllMarker: effectiveMarkerDate.map(ConversationDeleteAllMarker.init(deletedAt:)),
            deleteAllMarkerData: markerResult.data,
            attachmentData: attachmentResult.data,
            attachmentPlaceholders: attachmentResult.placeholders,
            attachmentConversationIds: attachmentResult.conversationIds,
            purgeMarker: purgeMarker,
            folderState: try loadConversationFolderState(in: documentsURL)
        )
    }

    func loadConversations(in documentsURL: URL) throws -> RecordFiles<Conversation> {
        let directory = documentsURL.appendingPathComponent("Conversations", isDirectory: true)
        try requireDownloadedFile(at: directory)
        guard fileManager.fileExists(atPath: directory.path) else { return RecordFiles() }
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }
        try requireNoPlaceholders(in: files)
        let decoder = SyncJSONCoding.makeDecoder()
        var values: [UUID: Conversation] = [:]
        var dataById: [UUID: Data] = [:]
        for url in files where url.pathExtension == "json" {
            try requireDownloadedFile(at: url)
            let data = try Data(contentsOf: url)
            let conversation = try decoder.decode(Conversation.self, from: data)
            try conversation.validateContextMetadata()
            guard UUID(uuidString: url.deletingPathExtension().lastPathComponent) == conversation.id else {
                throw CloudSyncError.invalidConversationData
            }
            guard values[conversation.id] == nil else {
                throw CloudSyncError.invalidConversationData
            }
            values[conversation.id] = conversation
            dataById[conversation.id] = data
        }
        return RecordFiles(values: values, data: dataById)
    }

    func loadTombstones(in documentsURL: URL) throws -> TombstoneFiles {
        let legacyURL = documentsURL.appendingPathComponent("ConversationTombstones.json")
        try requireDownloadedFile(at: legacyURL)
        let legacyData = try dataIfPresent(at: legacyURL)
        let decoder = SyncJSONCoding.makeDecoder()
        var tombstones = try legacyData.map { try decoder.decode([ConversationTombstone].self, from: $0) } ?? []
        let directory = documentsURL.appendingPathComponent("ConversationTombstones", isDirectory: true)
        try requireDownloadedFile(at: directory)
        guard fileManager.fileExists(atPath: directory.path) else {
            return TombstoneFiles(values: tombstones, data: [:], legacyData: legacyData)
        }
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        try requireNoPlaceholders(in: files)
        var dataById: [UUID: Data] = [:]
        for url in files where url.pathExtension == "json" {
            try requireDownloadedFile(at: url)
            let data = try Data(contentsOf: url)
            let tombstone = try decoder.decode(ConversationTombstone.self, from: data)
            guard UUID(uuidString: url.deletingPathExtension().lastPathComponent) == tombstone.conversationId else {
                throw CloudSyncError.cloudContentChanged
            }
            tombstones.append(tombstone)
            dataById[tombstone.conversationId] = data
        }
        return TombstoneFiles(values: tombstones, data: dataById, legacyData: legacyData)
    }

    func loadDeleteAllMarker(in documentsURL: URL) throws -> MarkerFile {
        let url = documentsURL.appendingPathComponent("ConversationDeleteAll.json")
        try requireDownloadedFile(at: url)
        guard let data = try dataIfPresent(at: url) else { return MarkerFile() }
        let marker = try SyncJSONCoding.makeDecoder().decode(ConversationDeleteAllMarker.self, from: data)
        return MarkerFile(value: marker, data: data)
    }

    func loadAttachments(
        in documentsURL: URL,
        conversations: [UUID: Conversation]
    ) throws -> AttachmentFiles {
        let resolver = AttachmentFileResolver(fileManager: fileManager, baseURL: documentsURL)
        let directory = try resolver.attachmentRoot()
        try requireDownloadedFile(at: directory)
        guard fileManager.fileExists(atPath: directory.path) else { return AttachmentFiles() }
        let folders = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let attachmentKeys = try referencedAttachmentKeys(in: Array(conversations.values))
        let requiredConversationIds = Set(attachmentKeys.map(\.conversationId))
        try requestAttachmentDirectories(in: folders, requiredConversationIds: requiredConversationIds)
        var dataByKey: [CloudAttachmentKey: Data] = [:]
        var placeholders = Set<CloudAttachmentKey>()
        var conversationIds = Set<UUID>()
        for folder in folders {
            if let placeholderName = placeholderFileName(for: folder),
               let conversationId = UUID(uuidString: placeholderName) {
                conversationIds.insert(conversationId)
                continue
            }
            let conversationId = try loadAttachmentFolder(
                folder,
                resolver: resolver,
                dataByKey: &dataByKey,
                placeholders: &placeholders
            )
            conversationIds.insert(conversationId)
        }
        return AttachmentFiles(
            data: dataByKey,
            placeholders: placeholders,
            conversationIds: conversationIds
        )
    }

}

// MARK: - Apply

private extension CloudSyncManager {
    func validateUnchanged(
        _ current: ConversationCloudSyncSnapshot,
        comparedTo snapshot: ConversationCloudSyncSnapshot,
        output: ConversationCloudSyncOutput
    ) throws {
        guard current.manifestData == snapshot.manifestData,
              current.folderState == snapshot.folderState,
              current.conversationData == snapshot.conversationData,
              current.tombstoneData == snapshot.tombstoneData,
              current.legacyTombstoneData == snapshot.legacyTombstoneData,
              current.deleteAllMarkerData == snapshot.deleteAllMarkerData,
              current.purgeMarker == snapshot.purgeMarker else {
            throw CloudSyncError.cloudContentChanged
        }
        guard current.attachmentData == snapshot.attachmentData,
              current.attachmentPlaceholders == snapshot.attachmentPlaceholders,
              current.attachmentConversationIds == snapshot.attachmentConversationIds else {
            throw CloudSyncError.cloudContentChanged
        }
        try validateFolderTransition(output, from: snapshot)
    }

    func apply(
        _ output: ConversationCloudSyncOutput,
        snapshot: ConversationCloudSyncSnapshot,
        containerURL: URL
    ) throws {
        try Task.checkCancellation()
        try validateOutput(output)
        if let purgeDate = snapshot.purgeMarker?.deletedAt,
           output.conversations.contains(where: { $0.updatedAt <= purgeDate }) {
            throw CloudSyncError.staleConversationRevision
        }
        try validate(snapshot.session)
        let documentsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
        try fileManager.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        try writeManifestIfNeeded(snapshot: snapshot, documentsURL: documentsURL)
        try validate(snapshot.session)
        try writeAttachments(output.attachments, session: snapshot.session, documentsURL: documentsURL)
        try validate(snapshot.session)
        try writeTombstones(output.tombstones, session: snapshot.session, documentsURL: documentsURL)
        try validate(snapshot.session)
        try writeMarker(output.deleteAllMarker, session: snapshot.session, documentsURL: documentsURL)
        try validate(snapshot.session)
        try writeConversationFolderState(output.folderState, replacing: snapshot.folderState, in: documentsURL) {
            try validate(snapshot.session)
        }
        try writeConversations(output, session: snapshot.session, documentsURL: documentsURL)
        try validate(snapshot.session)
        try deleteUnreferencedAttachments(output: output, snapshot: snapshot, documentsURL: documentsURL)
        try validate(snapshot.session)
        try deleteRemovedConversations(output: output, snapshot: snapshot, documentsURL: documentsURL)
        try validate(snapshot.session)
    }

    func validateOutput(_ output: ConversationCloudSyncOutput) throws {
        let conversationIds = Set(output.conversations.map(\.id))
        guard conversationIds.count == output.conversations.count,
              Set(output.conversationData.keys) == conversationIds else {
            throw CloudSyncError.invalidConversationData
        }
        let decoder = SyncJSONCoding.makeDecoder()
        for conversation in output.conversations {
            guard let data = output.conversationData[conversation.id],
                  try decoder.decode(Conversation.self, from: data) == conversation else {
                throw CloudSyncError.invalidConversationData
            }
            try conversation.validateContextMetadata()
        }
        let requiredAttachmentKeys = try referencedAttachmentKeys(in: output.conversations)
        guard requiredAttachmentKeys == Set(output.attachments.keys) else {
            throw CloudSyncError.missingAttachment
        }
    }

    func writeManifestIfNeeded(
        snapshot: ConversationCloudSyncSnapshot,
        documentsURL: URL
    ) throws {
        let url = documentsURL.appendingPathComponent("SyncManifest.json")
        guard snapshot.manifestData == nil else { return }
        let data = try JSONEncoder().encode(CloudSyncManifest.current)
        try writeAndVerify(data, to: url)
        _ = try CloudSyncManifest.decode(Data(contentsOf: url))
    }

    func writeAttachments(
        _ attachments: [CloudAttachmentKey: Data],
        session: CloudSyncSession,
        documentsURL: URL
    ) throws {
        let resolver = AttachmentFileResolver(fileManager: fileManager, baseURL: documentsURL)
        _ = try resolver.attachmentRoot()
        for (key, data) in attachments {
            try Task.checkCancellation()
            try validate(session)
            let folder = try resolver.conversationDirectory(key.conversationId)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            let fileURL = try resolver.resolve(relativePath: ConversationAttachmentPath.relativePath(for: key))
            try writeAndVerify(data, to: fileURL)
            try validate(session)
        }
    }

    func writeTombstones(
        _ tombstones: [ConversationTombstone],
        session: CloudSyncSession,
        documentsURL: URL
    ) throws {
        let directory = documentsURL.appendingPathComponent("ConversationTombstones", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = SyncJSONCoding.makeEncoder()
        let decoder = SyncJSONCoding.makeDecoder()
        for tombstone in tombstones {
            try Task.checkCancellation()
            try validate(session)
            let url = directory.appendingPathComponent("\(tombstone.conversationId.uuidString).json")
            let data = try encoder.encode(tombstone)
            try writeAndVerify(data, to: url)
            _ = try decoder.decode(ConversationTombstone.self, from: Data(contentsOf: url))
            try validate(session)
        }
    }

    func writeMarker(
        _ marker: ConversationDeleteAllMarker?,
        session: CloudSyncSession,
        documentsURL: URL
    ) throws {
        guard let marker else { return }
        try validate(session)
        let url = documentsURL.appendingPathComponent("ConversationDeleteAll.json")
        let data = try SyncJSONCoding.makeEncoder().encode(marker)
        try writeAndVerify(data, to: url)
        _ = try SyncJSONCoding.makeDecoder().decode(
            ConversationDeleteAllMarker.self,
            from: Data(contentsOf: url)
        )
        try validate(session)
    }

    func writeConversations(
        _ output: ConversationCloudSyncOutput,
        session: CloudSyncSession,
        documentsURL: URL
    ) throws {
        let directory = documentsURL.appendingPathComponent("Conversations", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let decoder = SyncJSONCoding.makeDecoder()
        for conversation in output.conversations {
            try Task.checkCancellation()
            try validate(session)
            let url = directory.appendingPathComponent("\(conversation.id.uuidString).json")
            guard let data = output.conversationData[conversation.id] else {
                throw CloudSyncError.invalidConversationData
            }
            try writeAndVerify(data, to: url)
            guard try decoder.decode(Conversation.self, from: Data(contentsOf: url)) == conversation else {
                throw CloudSyncError.invalidConversationData
            }
            try validate(session)
        }
    }

    func deleteRemovedConversations(
        output: ConversationCloudSyncOutput,
        snapshot: ConversationCloudSyncSnapshot,
        documentsURL: URL
    ) throws {
        let survivingIds = Set(output.conversations.map(\.id))
        let removedIds = Set(snapshot.conversations.keys).subtracting(survivingIds)
        let conversationsURL = documentsURL.appendingPathComponent("Conversations", isDirectory: true)
        let resolver = AttachmentFileResolver(fileManager: fileManager, baseURL: documentsURL)
        for id in removedIds {
            try Task.checkCancellation()
            try validate(snapshot.session)
            try removeDirectlyIfPresent(at: conversationsURL.appendingPathComponent("\(id.uuidString).json"))
            try removeDirectlyIfPresent(at: resolver.conversationDirectory(id))
            try validate(snapshot.session)
        }
    }

    func deleteUnreferencedAttachments(
        output: ConversationCloudSyncOutput,
        snapshot: ConversationCloudSyncSnapshot,
        documentsURL: URL
    ) throws {
        let referencedKeys = Set(output.attachments.keys)
        let existingKeys = Set(snapshot.attachmentData.keys).union(snapshot.attachmentPlaceholders)
        let resolver = AttachmentFileResolver(fileManager: fileManager, baseURL: documentsURL)
        for key in existingKeys.subtracting(referencedKeys) {
            try Task.checkCancellation()
            try validate(snapshot.session)
            let folder = try resolver.conversationDirectory(key.conversationId)
            let fileURL = try resolver.resolve(relativePath: ConversationAttachmentPath.relativePath(for: key))
            let placeholderPath = "Attachments/\(key.conversationId.uuidString)/.\(key.fileName).icloud"
            let placeholderURL = try resolver.resolve(relativePath: placeholderPath)
            try removeDirectlyIfPresent(at: fileURL)
            try removeDirectlyIfPresent(at: placeholderURL)
            if let contents = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil),
               contents.isEmpty {
                try removeDirectlyIfPresent(at: folder)
            }
            try validate(snapshot.session)
        }
    }

    func writeAndVerify(_ data: Data, to url: URL) throws {
        if try dataIfPresent(at: url) != data {
            try data.write(to: url, options: .atomic)
        }
        guard try Data(contentsOf: url) == data else {
            throw CloudSyncError.cloudContentChanged
        }
    }

    func removeDirectlyIfPresent(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
        guard !fileManager.fileExists(atPath: url.path) else {
            throw CloudSyncError.cloudContentChanged
        }
    }
}

// MARK: - Helpers

private extension CloudSyncManager {
    nonisolated struct RecordFiles<Value: Sendable>: Sendable {
        var values: [UUID: Value] = [:]
        var data: [UUID: Data] = [:]
    }

    nonisolated struct TombstoneFiles: Sendable {
        var values: [ConversationTombstone] = []
        var data: [UUID: Data] = [:]
        var legacyData: Data?
    }

    nonisolated struct MarkerFile: Sendable {
        var value: ConversationDeleteAllMarker?
        var data: Data?
    }

    nonisolated struct AttachmentFiles: Sendable {
        var data: [CloudAttachmentKey: Data] = [:]
        var placeholders: Set<CloudAttachmentKey> = []
        var conversationIds: Set<UUID> = []
    }

    func referencedAttachmentKeys(in conversations: [Conversation]) throws -> Set<CloudAttachmentKey> {
        var keys = Set<CloudAttachmentKey>()
        for conversation in conversations {
            for attachment in conversation.messages.flatMap(\.attachments) {
                if let key = try ConversationAttachmentPath.key(for: attachment, conversationId: conversation.id) {
                    keys.insert(key)
                }
            }
        }
        return keys
    }

}
