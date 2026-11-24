//
//  ConversationCloudSyncSnapshot.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 10/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

nonisolated struct CloudSyncSession: Equatable, Sendable {
    let containerURL: URL
    let identity: Data
}

nonisolated struct CloudAttachmentKey: Hashable, Sendable {
    let conversationId: UUID
    let fileName: String
}

nonisolated struct ConversationCloudSyncSnapshot: Sendable {
    let session: CloudSyncSession
    let manifestData: Data?
    let conversations: [UUID: Conversation]
    let conversationData: [UUID: Data]
    let tombstones: [ConversationTombstone]
    let tombstoneData: [UUID: Data]
    let legacyTombstoneData: Data?
    let deleteAllMarker: ConversationDeleteAllMarker?
    let deleteAllMarkerData: Data?
    let attachmentData: [CloudAttachmentKey: Data]
    let attachmentPlaceholders: Set<CloudAttachmentKey>
    let attachmentConversationIds: Set<UUID>
    var purgeMarker: CloudPurgeMarker?
    var folderState: ConversationFolderState

    init(
        session: CloudSyncSession,
        manifestData: Data?,
        conversations: [UUID: Conversation],
        conversationData: [UUID: Data],
        tombstones: [ConversationTombstone],
        tombstoneData: [UUID: Data],
        legacyTombstoneData: Data?,
        deleteAllMarker: ConversationDeleteAllMarker?,
        deleteAllMarkerData: Data?,
        attachmentData: [CloudAttachmentKey: Data],
        attachmentPlaceholders: Set<CloudAttachmentKey>,
        attachmentConversationIds: Set<UUID> = [],
        purgeMarker: CloudPurgeMarker? = nil,
        folderState: ConversationFolderState = ConversationFolderState()
    ) {
        self.session = session
        self.manifestData = manifestData
        self.conversations = conversations
        self.conversationData = conversationData
        self.tombstones = tombstones
        self.tombstoneData = tombstoneData
        self.legacyTombstoneData = legacyTombstoneData
        self.deleteAllMarker = deleteAllMarker
        self.deleteAllMarkerData = deleteAllMarkerData
        self.attachmentData = attachmentData
        self.attachmentPlaceholders = attachmentPlaceholders
        self.attachmentConversationIds = attachmentConversationIds
        self.purgeMarker = purgeMarker
        self.folderState = folderState
    }
}

nonisolated struct ConversationCloudSyncOutput: Sendable {
    let conversations: [Conversation]
    let conversationData: [UUID: Data]
    let tombstones: [ConversationTombstone]
    let deleteAllMarker: ConversationDeleteAllMarker?
    let attachments: [CloudAttachmentKey: Data]
    var folderState = ConversationFolderState()
}

nonisolated enum ConversationAttachmentPath {
    static func key(for attachment: ChatMessage.Attachment) throws -> CloudAttachmentKey? {
        guard !attachment.fileRelativePath.isEmpty else { return nil }
        let components = (attachment.fileRelativePath as NSString).pathComponents
        guard components.count == 3,
              components[0] == "Attachments",
              let conversationId = UUID(uuidString: components[1]),
              components[2] != ".",
              components[2] != "..",
              !components[2].contains("/"),
              !components[2].contains("\\"),
              !components[2].contains("%"),
              !isICloudPlaceholderFileName(components[2]) else {
            throw CloudSyncError.invalidAttachmentPath
        }
        let key = CloudAttachmentKey(conversationId: conversationId, fileName: components[2])
        guard attachment.fileRelativePath == relativePath(for: key) else {
            throw CloudSyncError.invalidAttachmentPath
        }
        return key
    }

    static func key(
        for attachment: ChatMessage.Attachment,
        conversationId: UUID
    ) throws -> CloudAttachmentKey? {
        guard let key = try key(for: attachment) else { return nil }
        guard key.conversationId == conversationId else {
            throw CloudSyncError.invalidAttachmentPath
        }
        return key
    }

    static func relativePath(for key: CloudAttachmentKey) -> String {
        "Attachments/\(key.conversationId.uuidString)/\(key.fileName)"
    }

    static func relativePath(
        for attachment: ChatMessage.Attachment,
        conversationId: UUID
    ) -> String {
        let fileName = "\(attachment.id.uuidString).\(fileExtension(for: attachment))"
        return relativePath(for: CloudAttachmentKey(conversationId: conversationId, fileName: fileName))
    }

    private static func fileExtension(for attachment: ChatMessage.Attachment) -> String {
        switch attachment.mimeType {
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "application/pdf": return "pdf"
        default:
            let candidate = (attachment.fileName as NSString).pathExtension.lowercased()
            let allowed = candidate.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains)
            return !candidate.isEmpty && allowed ? candidate : "bin"
        }
    }

    private static func isICloudPlaceholderFileName(_ fileName: String) -> Bool {
        fileName.hasPrefix(".") && fileName.hasSuffix(".icloud")
    }
}
