//
//  ConversationStorage+ImportBatch.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 11/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

// MARK: - Import Batch

extension ConversationStorage {
    func importBatch(
        _ conversations: [Conversation],
        organization: ConversationFolderSnapshot = .init(folders: [], memberships: [])
    ) throws -> [Conversation] {
        try ensureDirectoryExists()
        let existingIds = Set(try loadLocalConversations().map(\.id))
        let importedIds = conversations.map(\.id)
        guard Set(importedIds).count == importedIds.count,
              importedIds.allSatisfy({ !existingIds.contains($0) }) else {
            throw CloudSyncError.invalidConversationData
        }
        let barrier = try newestMarker(loadDeleteAllMarker(), loadLocalResetMarker())?.deletedAt
        // A full millisecond survives the sync date formatter's round trip, including on a fast remote clock.
        let minimumRevision = barrier?.addingTimeInterval(0.001)
        let canonical = try conversations.map { conversation in
            var conversation = conversation
            if let minimumRevision {
                conversation.updatedAt = max(conversation.updatedAt, minimumRevision)
            }
            return try canonicalConversation(conversation)
        }
        let attachmentKeys = try canonical.reduce(into: Set<CloudAttachmentKey>()) { keys, item in
            keys.formUnion(try self.attachmentKeys(in: [item.conversation]))
        }
        let verification = ConversationLocalTransaction.Verification(
            conversations: Dictionary(uniqueKeysWithValues: canonical.map { ($0.conversation.id, $0.conversation) }),
            attachments: canonical.reduce(into: [CloudAttachmentKey: Data]()) { data, item in
                data.merge(item.attachmentData) { _, imported in imported }
            }
        )
        let transaction = try ConversationLocalTransaction(
            fileManager: fileManager,
            documentsURL: documentsURL,
            attachmentKeys: attachmentKeys
        )
        do {
            try importFolderState(
                importOrganization(organization, minimumRevision: minimumRevision),
                conversationIDs: Set(importedIds)
            )
            for item in canonical {
                try persistLocalAttachments(item.attachmentData)
                try saveLocal(item.conversation)
            }
            try transaction.commit(verifying: verification)
        } catch {
            try transaction.rollback()
            throw error
        }
        return canonical.map(\.conversation)
    }

    private func importOrganization(
        _ organization: ConversationFolderSnapshot,
        minimumRevision: Date?
    ) -> ConversationFolderSnapshot {
        guard let minimumRevision else { return organization }
        let folders = organization.folders.map { folder in
            ConversationFolder(id: folder.id, name: folder.name, updatedAt: max(folder.updatedAt, minimumRevision))
        }
        let memberships = organization.memberships.map { membership in
            ConversationFolderMembership(
                conversationId: membership.conversationId,
                folderId: membership.folderId,
                updatedAt: max(membership.updatedAt, minimumRevision)
            )
        }
        return ConversationFolderSnapshot(folders: folders, memberships: memberships)
    }
}
