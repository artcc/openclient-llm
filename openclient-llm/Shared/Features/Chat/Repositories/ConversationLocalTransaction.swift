//
//  ConversationLocalTransaction.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 10/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

nonisolated struct ConversationLocalTransaction {
    struct Verification {
        var conversations: [UUID: Conversation] = [:]
        var pendingMutationBases: [UUID: Conversation] = [:]
        var attachments: [CloudAttachmentKey: Data] = [:]
        var absentConversationIds: Set<UUID> = []
        var absentPendingMutationIds: Set<UUID> = []
        var absentPendingDeletionIds: Set<UUID> = []
        var absentAttachmentKeys: Set<CloudAttachmentKey> = []
        var exactConversationSet = false
        var emptyConversations = false
        var emptyPendingMutations = false
        var emptyAttachments = false
    }

    // MARK: - Properties

    private static let defaultItemNames = [
        "Conversations",
        ConversationFolderState.fileName,
        "ConversationTombstones.json",
        "ConversationDeleteAll.json",
        "ConversationLocalReset.json",
        "ConversationPendingMutations",
        "ConversationPendingDeletions"
    ]

    private struct Manifest: Codable {
        let itemNames: [String]
        let attachmentPaths: [String]
    }

    private let fileManager: FileManager
    private let documentsURL: URL
    private let backupURL: URL

    // MARK: - Init

    init(
        fileManager: FileManager,
        documentsURL: URL,
        attachmentKeys: Set<CloudAttachmentKey> = [],
        backsUpAllAttachments: Bool = false
    ) throws {
        self.fileManager = fileManager
        self.documentsURL = documentsURL
        let transactionsURL = Self.transactionsDirectory(documentsURL: documentsURL)
        let identifier = UUID().uuidString
        let stagingURL = transactionsURL.appendingPathComponent("\(identifier).staging", isDirectory: true)
        let backupURL = transactionsURL.appendingPathComponent("\(identifier).pending", isDirectory: true)
        self.backupURL = backupURL

        do {
            try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
            let itemNames = Self.defaultItemNames + (backsUpAllAttachments ? ["Attachments"] : [])
            for itemName in itemNames {
                let sourceURL = documentsURL.appendingPathComponent(itemName)
                guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
                let destinationURL = stagingURL.appendingPathComponent(itemName)
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                try Self.verifyCopy(sourceURL: sourceURL, destinationURL: destinationURL, fileManager: fileManager)
            }
            let attachmentPaths = backsUpAllAttachments
                ? []
                : attachmentKeys.map(ConversationAttachmentPath.relativePath).sorted()
            try Self.copyAttachments(
                at: attachmentPaths,
                documentsURL: documentsURL,
                stagingURL: stagingURL,
                fileManager: fileManager
            )
            let manifest = Manifest(itemNames: itemNames, attachmentPaths: attachmentPaths)
            try JSONEncoder().encode(manifest).write(
                to: stagingURL.appendingPathComponent("Manifest.json"),
                options: .atomic
            )
            try fileManager.moveItem(at: stagingURL, to: backupURL)
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            try? fileManager.removeItem(at: backupURL)
            throw error
        }
    }

    // MARK: - Transaction

    static func recoverPendingTransactions(fileManager: FileManager, documentsURL: URL) throws {
        let transactionsURL = transactionsDirectory(documentsURL: documentsURL)
        guard fileManager.fileExists(atPath: transactionsURL.path) else { return }
        let backups = try fileManager.contentsOfDirectory(at: transactionsURL, includingPropertiesForKeys: nil)
        for backupURL in backups {
            let values = try backupURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
            switch backupURL.pathExtension {
            case "staging", "committed":
                try fileManager.removeItem(at: backupURL)
                continue
            case "pending":
                break
            default:
                continue
            }
            let transaction = ConversationLocalTransaction(
                fileManager: fileManager,
                documentsURL: documentsURL,
                backupURL: backupURL
            )
            try transaction.rollback()
        }
    }

    func commit(verifying verification: Verification) throws {
        try verify(verification)
        try disposeRecovery()
    }

    func commit() throws {
        try verifyCurrentStore()
        try disposeRecovery()
    }

    private func disposeRecovery() throws {
        let committedURL = backupURL
            .deletingPathExtension()
            .appendingPathExtension("committed")
        try fileManager.moveItem(at: backupURL, to: committedURL)
        try? fileManager.removeItem(at: committedURL)
    }

    func rollback() throws {
        let manifest = try loadManifest()
        let restoreURL = backupURL.appendingPathComponent("Restore", isDirectory: true)
        let displacedURL = backupURL.appendingPathComponent("Displaced", isDirectory: true)
        try removeIfPresent(restoreURL)
        try removeIfPresent(displacedURL)
        try fileManager.createDirectory(at: restoreURL, withIntermediateDirectories: true)

        for itemName in manifest.itemNames {
            let sourceURL = backupURL.appendingPathComponent(itemName)
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
            let stagedURL = restoreURL.appendingPathComponent(itemName)
            try fileManager.copyItem(at: sourceURL, to: stagedURL)
            guard fileManager.contentsEqual(atPath: sourceURL.path, andPath: stagedURL.path) else {
                throw CloudSyncError.invalidConversationData
            }
        }

        let backupResolver = AttachmentFileResolver(fileManager: fileManager, baseURL: backupURL)
        for relativePath in manifest.attachmentPaths {
            let sourceURL = try backupResolver.resolve(relativePath: relativePath)
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
            let stagedURL = restoreURL.appendingPathComponent(relativePath)
            try fileManager.createDirectory(
                at: stagedURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: sourceURL, to: stagedURL)
            try Self.verifyCopy(sourceURL: sourceURL, destinationURL: stagedURL, fileManager: fileManager)
        }

        for itemName in manifest.itemNames {
            let destinationURL = documentsURL.appendingPathComponent(itemName)
            let displacedItemURL = displacedURL.appendingPathComponent(itemName)
            let stagedURL = restoreURL.appendingPathComponent(itemName)
            try restoreItem(destinationURL: destinationURL, stagedURL: stagedURL, displacedURL: displacedItemURL)
        }

        let liveResolver = AttachmentFileResolver(fileManager: fileManager, baseURL: documentsURL)
        for relativePath in manifest.attachmentPaths {
            let destinationURL = try liveResolver.resolve(relativePath: relativePath)
            let stagedURL = restoreURL.appendingPathComponent(relativePath)
            let displacedItemURL = displacedURL.appendingPathComponent(relativePath)
            try restoreItem(destinationURL: destinationURL, stagedURL: stagedURL, displacedURL: displacedItemURL)
        }
        try fileManager.removeItem(at: backupURL)
    }
}

// MARK: - Private

private nonisolated extension ConversationLocalTransaction {
    init(fileManager: FileManager, documentsURL: URL, backupURL: URL) {
        self.fileManager = fileManager
        self.documentsURL = documentsURL
        self.backupURL = backupURL
    }

    static func transactionsDirectory(documentsURL: URL) -> URL {
        documentsURL
            .appendingPathComponent("ConversationRecovery", isDirectory: true)
            .appendingPathComponent("Transactions", isDirectory: true)
    }

    static func copyAttachments(
        at relativePaths: [String],
        documentsURL: URL,
        stagingURL: URL,
        fileManager: FileManager
    ) throws {
        let sourceResolver = AttachmentFileResolver(fileManager: fileManager, baseURL: documentsURL)
        for relativePath in relativePaths {
            let sourceURL = try sourceResolver.resolve(relativePath: relativePath)
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
            let destinationURL = stagingURL.appendingPathComponent(relativePath)
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            try verifyCopy(sourceURL: sourceURL, destinationURL: destinationURL, fileManager: fileManager)
        }
    }

    static func verifyCopy(
        sourceURL: URL,
        destinationURL: URL,
        fileManager: FileManager
    ) throws {
        guard fileManager.contentsEqual(atPath: sourceURL.path, andPath: destinationURL.path) else {
            throw CloudSyncError.invalidConversationData
        }
    }

    private func loadManifest() throws -> Manifest {
        let data = try Data(contentsOf: backupURL.appendingPathComponent("Manifest.json"))
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    func verify(_ verification: Verification) throws {
        let decoder = SyncJSONCoding.makeDecoder()
        try verifyConversations(verification, decoder: decoder)
        try verifyPendingMutations(verification, decoder: decoder)
        try verifyPendingDeletions(verification)
        try verifyAttachments(verification)
        try verifyEmptyDirectories(verification)
    }

    func verifyConversations(_ verification: Verification, decoder: JSONDecoder) throws {
        for (id, expected) in verification.conversations {
            let url = documentsURL.appendingPathComponent("Conversations/\(id.uuidString).json")
            let decoded = try decoder.decode(Conversation.self, from: Data(contentsOf: url))
            try decoded.validateContextMetadata()
            guard decoded == expected else { throw CloudSyncError.invalidConversationData }
        }
        for id in verification.absentConversationIds {
            let url = documentsURL.appendingPathComponent("Conversations/\(id.uuidString).json")
            guard !fileManager.fileExists(atPath: url.path) else {
                throw CloudSyncError.invalidConversationData
            }
        }
        if verification.exactConversationSet {
            let ids = Set(try decodedConversations(
                in: documentsURL.appendingPathComponent("Conversations", isDirectory: true),
                decoder: decoder
            ).map(\.id))
            guard ids == Set(verification.conversations.keys) else {
                throw CloudSyncError.invalidConversationData
            }
        }
    }

    func verifyPendingMutations(_ verification: Verification, decoder: JSONDecoder) throws {
        for (id, expected) in verification.pendingMutationBases {
            let url = documentsURL.appendingPathComponent("ConversationPendingMutations/\(id.uuidString).json")
            let decoded = try decoder.decode(Conversation.self, from: Data(contentsOf: url))
            try decoded.validateContextMetadata()
            guard decoded == expected else { throw CloudSyncError.invalidConversationData }
        }
        for id in verification.absentPendingMutationIds {
            let url = documentsURL.appendingPathComponent("ConversationPendingMutations/\(id.uuidString).json")
            guard !fileManager.fileExists(atPath: url.path) else {
                throw CloudSyncError.invalidConversationData
            }
        }
    }

    func verifyPendingDeletions(_ verification: Verification) throws {
        for id in verification.absentPendingDeletionIds {
            let url = documentsURL.appendingPathComponent("ConversationPendingDeletions/\(id.uuidString).json")
            guard !fileManager.fileExists(atPath: url.path) else {
                throw CloudSyncError.invalidConversationData
            }
        }
    }

    func verifyAttachments(_ verification: Verification) throws {
        let resolver = AttachmentFileResolver(fileManager: fileManager, baseURL: documentsURL)
        for (key, expected) in verification.attachments {
            let url = try resolver.resolve(relativePath: ConversationAttachmentPath.relativePath(for: key))
            guard try Data(contentsOf: url) == expected else { throw CloudSyncError.missingAttachment }
        }
        for key in verification.absentAttachmentKeys {
            let url = try resolver.resolve(relativePath: ConversationAttachmentPath.relativePath(for: key))
            guard !fileManager.fileExists(atPath: url.path) else { throw CloudSyncError.missingAttachment }
        }
    }

    func verifyEmptyDirectories(_ verification: Verification) throws {
        if verification.emptyConversations {
            try requireEmptyDirectory(named: "Conversations")
        }
        if verification.emptyPendingMutations {
            try requireEmptyDirectory(named: "ConversationPendingMutations")
        }
        if verification.emptyAttachments {
            try requireEmptyDirectory(named: "Attachments")
        }
    }

    func verifyCurrentStore() throws {
        let decoder = SyncJSONCoding.makeDecoder()
        let conversations = try decodedConversations(
            in: documentsURL.appendingPathComponent("Conversations", isDirectory: true),
            decoder: decoder
        )
        _ = try decodedConversations(
            in: documentsURL.appendingPathComponent("ConversationPendingMutations", isDirectory: true),
            decoder: decoder
        )
        let resolver = AttachmentFileResolver(fileManager: fileManager, baseURL: documentsURL)
        for conversation in conversations {
            for attachment in conversation.messages.flatMap(\.attachments) {
                guard let key = try ConversationAttachmentPath.key(for: attachment) else {
                    throw CloudSyncError.missingAttachment
                }
                let url = try resolver.resolve(relativePath: ConversationAttachmentPath.relativePath(for: key))
                _ = try Data(contentsOf: url)
            }
        }
    }

    func decodedConversations(in directory: URL, decoder: JSONDecoder) throws -> [Conversation] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ).filter { $0.pathExtension == "json" }.map { url in
            let conversation = try decoder.decode(Conversation.self, from: Data(contentsOf: url))
            try conversation.validateContextMetadata()
            guard UUID(uuidString: url.deletingPathExtension().lastPathComponent) == conversation.id else {
                throw CloudSyncError.invalidConversationData
            }
            return conversation
        }
    }

    func requireEmptyDirectory(named name: String) throws {
        let url = documentsURL.appendingPathComponent(name, isDirectory: true)
        guard fileManager.fileExists(atPath: url.path) else { return }
        guard try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).isEmpty else {
            throw CloudSyncError.invalidConversationData
        }
    }

    func restoreItem(
        destinationURL: URL,
        stagedURL: URL,
        displacedURL: URL
    ) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.createDirectory(
                at: displacedURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: destinationURL, to: displacedURL)
        }
        do {
            if fileManager.fileExists(atPath: stagedURL.path) {
                try fileManager.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.moveItem(at: stagedURL, to: destinationURL)
            }
            try removeIfPresent(displacedURL)
        } catch {
            if fileManager.fileExists(atPath: displacedURL.path) {
                try fileManager.moveItem(at: displacedURL, to: destinationURL)
            }
            throw error
        }
    }

    func removeIfPresent(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}
