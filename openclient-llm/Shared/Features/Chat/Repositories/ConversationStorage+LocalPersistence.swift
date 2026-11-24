//
//  ConversationStorage+LocalPersistence.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 10/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import CryptoKit
import Foundation

// MARK: - Local Persistence

extension ConversationStorage {
    func makeEncoder() -> JSONEncoder {
        SyncJSONCoding.makeEncoder()
    }

    func makeDecoder() -> JSONDecoder {
        SyncJSONCoding.makeDecoder()
    }

    func ensureDirectoryExists() throws {
        try ConversationLocalTransaction.recoverPendingTransactions(
            fileManager: fileManager,
            documentsURL: documentsURL
        )
        guard !fileManager.fileExists(atPath: directoryURL.path) else { return }
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func loadLocalConversations() throws -> [Conversation] {
        Array(try loadLocalConversationFiles().values.values)
    }

    func loadLocalConversationFiles() throws -> ConversationFiles {
        let fileURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        var files = ConversationFiles()
        for url in fileURLs where url.pathExtension == "json" {
            let data = try Data(contentsOf: url)
            let conversation = try makeDecoder().decode(Conversation.self, from: data)
            try conversation.validateContextMetadata()
            guard UUID(uuidString: url.deletingPathExtension().lastPathComponent) == conversation.id,
                  files.values[conversation.id] == nil else {
                throw CloudSyncError.invalidConversationData
            }
            files.values[conversation.id] = conversation
            files.data[conversation.id] = data
        }
        return files
    }

    func loadLocalConversation(id: UUID) throws -> Conversation? {
        let url = conversationFileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let conversation = try makeDecoder().decode(Conversation.self, from: Data(contentsOf: url))
        try conversation.validateContextMetadata()
        guard conversation.id == id else { throw CloudSyncError.invalidConversationData }
        return conversation
    }

    func saveLocal(_ conversation: Conversation) throws {
        try writeIfChanged(
            makeEncoder().encode(conversation),
            to: conversationFileURL(for: conversation.id)
        )
    }

    func persistLocal(output: ConversationCloudSyncOutput) throws {
        try writeFolderState(output.folderState)
        for conversation in output.conversations {
            guard let data = output.conversationData[conversation.id] else {
                throw CloudSyncError.invalidConversationData
            }
            let url = conversationFileURL(for: conversation.id)
            try writeIfChanged(data, to: url)
            guard try makeDecoder().decode(Conversation.self, from: Data(contentsOf: url)) == conversation else {
                throw CloudSyncError.invalidConversationData
            }
        }
        try saveTombstones(output.tombstones)
        try cleanupLocalFiles(keeping: Set(output.conversations.map(\.id)))
    }

    func commitSynchronization(
        plan: SynchronizationPlan,
        snapshot: ConversationCloudSyncSnapshot
    ) throws {
        let output = plan.output
        try cloudSyncManager.validateConversationSyncOutput(output, basedOn: snapshot)
        let knownAttachmentKeys = Set(snapshot.attachmentData.keys)
            .union(snapshot.attachmentPlaceholders)
            .union(plan.localAttachmentKeys)
        let isLocalCurrent = try isLocalOutputCurrent(
            output,
            knownAttachmentKeys: knownAttachmentKeys
        ) && plan.resolvedPendingMutationIds.isEmpty && plan.resolvedPendingDeletionIds.isEmpty
        if let deletedAt = snapshot.deleteAllMarker?.deletedAt {
            try manageFolderRecovery(purgeThrough: deletedAt)
        }
        if isLocalCurrent {
            guard !isCloudOutputCurrent(output, snapshot: snapshot) else { return }
            try Task.checkCancellation()
            try cloudSyncManager.applyConversationSyncOutput(output, basedOn: snapshot)
            return
        }
        try commitSynchronizationTransaction(
            plan: plan,
            snapshot: snapshot,
            knownAttachmentKeys: knownAttachmentKeys
        )
    }

    func commitSynchronizationTransaction(
        plan: SynchronizationPlan,
        snapshot: ConversationCloudSyncSnapshot,
        knownAttachmentKeys: Set<CloudAttachmentKey>
    ) throws {
        let output = plan.output
        let transaction = try ConversationLocalTransaction(
            fileManager: fileManager,
            documentsURL: documentsURL,
            attachmentKeys: knownAttachmentKeys.union(output.attachments.keys)
        )
        do {
            try persistLocalAttachments(output.attachments)
            try persistLocal(output: output)
            try cleanupLocalAttachments(
                removing: knownAttachmentKeys,
                keeping: Set(output.attachments.keys),
                preserving: plan.localConflictAttachmentKeys
            )
            if let marker = output.deleteAllMarker {
                try saveDeleteAllMarker(marker)
            }
            for id in plan.resolvedPendingMutationIds {
                try removePendingMutation(conversationId: id)
            }
            for id in plan.resolvedPendingDeletionIds {
                try removePendingDeletion(conversationId: id)
            }
            try Task.checkCancellation()
            try cloudSyncManager.applyConversationSyncOutput(output, basedOn: snapshot)
            try transaction.commit(verifying: .init(
                conversations: Dictionary(uniqueKeysWithValues: output.conversations.map { ($0.id, $0) }),
                attachments: output.attachments,
                absentPendingMutationIds: plan.resolvedPendingMutationIds,
                absentPendingDeletionIds: plan.resolvedPendingDeletionIds,
                absentAttachmentKeys: knownAttachmentKeys.subtracting(output.attachments.keys),
                exactConversationSet: true,
                emptyPendingMutations: true
            ))
        } catch {
            do {
                try transaction.rollback()
            } catch let rollbackError {
                throw rollbackError
            }
            throw error
        }
    }

    func localAttachmentData(for key: CloudAttachmentKey) throws -> Data? {
        let relativePath = ConversationAttachmentPath.relativePath(for: key)
        let url = try attachmentFileResolver().resolve(relativePath: relativePath)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    func loadLocalAttachmentFiles() throws -> [CloudAttachmentKey: Data] {
        let resolver = attachmentFileResolver()
        let root = try resolver.attachmentRoot()
        guard fileManager.fileExists(atPath: root.path) else { return [:] }
        let folders = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        var result: [CloudAttachmentKey: Data] = [:]
        for folder in folders {
            let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true,
                  values.isSymbolicLink != true,
                  let conversationId = UUID(uuidString: folder.lastPathComponent) else { continue }
            let files = try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            for file in files {
                let fileValues = try file.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard fileValues.isDirectory != true else { continue }
                guard fileValues.isSymbolicLink != true else { throw CloudSyncError.invalidAttachmentPath }
                let key = CloudAttachmentKey(conversationId: conversationId, fileName: file.lastPathComponent)
                let relativePath = ConversationAttachmentPath.relativePath(for: key)
                result[key] = try Data(contentsOf: resolver.resolve(relativePath: relativePath))
            }
        }
        return result
    }

    func persistLocalAttachments(_ attachments: [CloudAttachmentKey: Data]) throws {
        for (key, data) in attachments {
            let resolver = attachmentFileResolver()
            let relativePath = ConversationAttachmentPath.relativePath(for: key)
            let url = try resolver.resolve(relativePath: relativePath)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let resolvedURL = try resolver.resolve(relativePath: relativePath)
            try writeIfChanged(data, to: resolvedURL)
            guard try Data(contentsOf: resolvedURL) == data else {
                throw CloudSyncError.missingAttachment
            }
        }
    }

    func persistLocalMutation(
        _ conversation: Conversation,
        replacing previous: Conversation,
        pendingBase: Conversation?,
        replacePendingBase: Bool = false,
        attachmentData: [CloudAttachmentKey: Data]
    ) throws {
        let conversation = try canonicalJSONConversation(conversation)
        let pendingBase = try pendingBase.map(canonicalJSONConversation)
        let previousKeys = try storedAttachmentKeys(in: previous)
        let retainedKeys = try attachmentKeys(in: [conversation])
        var expectedAttachments = try localAttachmentData(for: retainedKeys)
        for (key, data) in attachmentData {
            if let existing = expectedAttachments[key], existing != data {
                throw CloudSyncError.invalidConversationData
            }
            expectedAttachments[key] = data
        }
        let transaction = try ConversationLocalTransaction(
            fileManager: fileManager,
            documentsURL: documentsURL,
            attachmentKeys: previousKeys.union(retainedKeys)
        )
        do {
            try persistLocalAttachments(attachmentData)
            if let pendingBase {
                if replacePendingBase {
                    try replacePendingMutationBase(pendingBase)
                } else {
                    try savePendingMutationBase(pendingBase)
                }
            }
            try saveLocal(conversation)
            try removeLocalAttachments(previousKeys.subtracting(retainedKeys))
            let expectedPendingBase: Conversation?
            if let pendingBase {
                expectedPendingBase = pendingBase
            } else {
                expectedPendingBase = try loadPendingMutationBase(conversationId: conversation.id)
            }
            try transaction.commit(verifying: .init(
                conversations: [conversation.id: conversation],
                pendingMutationBases: expectedPendingBase.map { [conversation.id: $0] } ?? [:],
                attachments: expectedAttachments,
                absentAttachmentKeys: previousKeys.subtracting(retainedKeys)
            ))
        } catch {
            try transaction.rollback()
            throw error
        }
    }

    func persistNewLocalConversation(
        _ conversation: Conversation,
        attachmentData: [CloudAttachmentKey: Data],
        creationPlacement: ConversationCreationPlacement? = nil,
        cloud: ConversationCloudSyncSnapshot? = nil
    ) throws {
        let conversation = try canonicalJSONConversation(conversation)
        let attachmentKeys = try attachmentKeys(in: [conversation])
        var expectedAttachments = try localAttachmentData(for: attachmentKeys)
        for (key, data) in attachmentData {
            if let existing = expectedAttachments[key], existing != data {
                throw CloudSyncError.invalidConversationData
            }
            expectedAttachments[key] = data
        }
        let transaction = try ConversationLocalTransaction(
            fileManager: fileManager,
            documentsURL: documentsURL,
            attachmentKeys: attachmentKeys
        )
        do {
            try persistLocalAttachments(attachmentData)
            try saveLocal(conversation)
            try applyCreationPlacement(creationPlacement, to: conversation.id, cloud: cloud)
            try transaction.commit(verifying: .init(
                conversations: [conversation.id: conversation],
                attachments: expectedAttachments
            ))
        } catch {
            try transaction.rollback()
            throw error
        }
    }

    func removeLocalAttachments(_ keys: Set<CloudAttachmentKey>) throws {
        let resolver = attachmentFileResolver()
        for key in keys {
            let relativePath = ConversationAttachmentPath.relativePath(for: key)
            let url = try resolver.resolve(relativePath: relativePath)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            try preserveAttachmentForRecovery(Data(contentsOf: url), key: key)
            try fileManager.removeItem(at: url)
            let directory = try resolver.conversationDirectory(key.conversationId)
            if try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).isEmpty {
                try fileManager.removeItem(at: directory)
            }
        }
    }

    func localAttachmentData(for keys: Set<CloudAttachmentKey>) throws -> [CloudAttachmentKey: Data] {
        var result: [CloudAttachmentKey: Data] = [:]
        for key in keys {
            if let data = try localAttachmentData(for: key) {
                result[key] = data
            }
        }
        return result
    }

    func canonicalJSONConversation(_ conversation: Conversation) throws -> Conversation {
        try makeDecoder().decode(Conversation.self, from: makeEncoder().encode(conversation))
    }

    func cleanupLocalFiles(keeping ids: Set<UUID>) throws {
        let fileURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        for url in fileURLs where url.pathExtension == "json" {
            guard let uuid = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { continue }
            if !ids.contains(uuid) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    func cleanupLocalAttachments(
        removing knownKeys: Set<CloudAttachmentKey>,
        keeping retainedKeys: Set<CloudAttachmentKey>,
        preserving recoveryKeys: Set<CloudAttachmentKey>
    ) throws {
        let resolver = attachmentFileResolver()
        let root = try resolver.attachmentRoot()
        guard fileManager.fileExists(atPath: root.path) else { return }
        let folders = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        for folder in folders {
            let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true,
                  values.isSymbolicLink != true,
                  let conversationId = UUID(uuidString: folder.lastPathComponent) else { continue }
            _ = try resolver.conversationDirectory(conversationId)
            let files = try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            for file in files {
                let fileValues = try file.resourceValues(forKeys: [.isSymbolicLinkKey])
                guard fileValues.isSymbolicLink != true else { throw CloudSyncError.invalidAttachmentPath }
                let key = CloudAttachmentKey(conversationId: conversationId, fileName: file.lastPathComponent)
                guard knownKeys.contains(key), !retainedKeys.contains(key) else { continue }
                let resolvedFile = try resolver.resolve(relativePath: ConversationAttachmentPath.relativePath(for: key))
                if recoveryKeys.contains(key) {
                    let data = try Data(contentsOf: resolvedFile)
                    try preserveAttachmentForRecovery(data, key: key)
                }
                try fileManager.removeItem(at: resolvedFile)
            }
            if try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).isEmpty {
                try fileManager.removeItem(at: folder)
            }
        }
    }

    func preserveRemovedCloudAttachments(
        output: ConversationCloudSyncOutput,
        snapshot: ConversationCloudSyncSnapshot,
        tombstones: [ConversationTombstone],
        marker: ConversationDeleteAllMarker?
    ) throws {
        let outputById = Dictionary(uniqueKeysWithValues: output.conversations.map { ($0.id, $0) })
        for cloudConversation in snapshot.conversations.values where shouldKeep(
            cloudConversation,
            tombstones: tombstones,
            marker: marker
        ) {
            guard let winner = outputById[cloudConversation.id], winner != cloudConversation else { continue }
            let removedKeys = try attachmentKeys(in: [cloudConversation])
                .subtracting(attachmentKeys(in: [winner]))
            if !removedKeys.isDisjoint(with: snapshot.attachmentPlaceholders) {
                throw CloudSyncError.requiredDownloadPending
            }
            for key in removedKeys {
                guard let data = snapshot.attachmentData[key] else { continue }
                try preserveAttachmentForRecovery(data, key: key)
            }
        }
    }

    func preserveForRecovery(_ data: Data, conversationId: UUID) throws {
        try fileManager.createDirectory(at: recoveryDirectoryURL, withIntermediateDirectories: true)
        let digest = recoveryDigest(for: data)
        let url = recoveryDirectoryURL.appendingPathComponent("\(conversationId.uuidString)-\(digest).json")
        try writeIfChanged(data, to: url)
        guard try Data(contentsOf: url) == data else {
            throw CloudSyncError.invalidConversationData
        }
    }

    func preserveAttachmentForRecovery(_ data: Data, key: CloudAttachmentKey) throws {
        let directory = recoveryDirectoryURL
            .appendingPathComponent("Attachments", isDirectory: true)
            .appendingPathComponent(key.conversationId.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(recoveryDigest(for: data))-\(key.fileName)")
        try writeIfChanged(data, to: url)
        guard try Data(contentsOf: url) == data else {
            throw CloudSyncError.missingAttachment
        }
    }

    func conversationFileURL(for id: UUID) -> URL {
        directoryURL.appendingPathComponent("\(id.uuidString).json")
    }

    func writeIfChanged(_ data: Data, to url: URL) throws {
        if let existing = try? Data(contentsOf: url), existing == data { return }
        try data.write(to: url, options: .atomic)
    }

    func isLocalOutputCurrent(
        _ output: ConversationCloudSyncOutput,
        knownAttachmentKeys: Set<CloudAttachmentKey>
    ) throws -> Bool {
        guard try readFolderState() == output.folderState,
              try loadLocalConversationFiles().data == output.conversationData,
              try loadTombstones() == output.tombstones,
              try loadDeleteAllMarker() == output.deleteAllMarker else {
            return false
        }
        for key in knownAttachmentKeys {
            let localData = try localAttachmentData(for: key)
            if localData != output.attachments[key] { return false }
        }
        return true
    }

    func isCloudOutputCurrent(
        _ output: ConversationCloudSyncOutput,
        snapshot: ConversationCloudSyncSnapshot
    ) -> Bool {
        guard snapshot.manifestData != nil,
              snapshot.folderState == output.folderState,
              snapshot.conversationData == output.conversationData,
              snapshot.attachmentData == output.attachments,
              snapshot.attachmentPlaceholders.isEmpty,
              snapshot.deleteAllMarker == output.deleteAllMarker else {
            return false
        }
        let encoder = makeEncoder()
        guard let tombstoneData = try? Dictionary(uniqueKeysWithValues: output.tombstones.map {
            ($0.conversationId, try encoder.encode($0))
        }) else {
            return false
        }
        return snapshot.tombstoneData == tombstoneData
    }

    func recoveryDigest(for data: Data) -> String {
        SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private func attachmentFileResolver() -> AttachmentFileResolver {
        AttachmentFileResolver(fileManager: fileManager, baseURL: documentsURL)
    }
}
