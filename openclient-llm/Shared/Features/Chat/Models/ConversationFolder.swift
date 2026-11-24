//
//  ConversationFolder.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 23/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

nonisolated struct ConversationFolder: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let name: String
    let updatedAt: Date
}

nonisolated struct ConversationFolderMembership: Codable, Equatable, Sendable {
    let conversationId: UUID
    let folderId: UUID?
    let updatedAt: Date
}

nonisolated struct ConversationFolderSnapshot: Equatable, Sendable {
    let folders: [ConversationFolder]
    let memberships: [ConversationFolderMembership]

    func folderID(for conversationID: UUID) -> UUID? {
        guard let id = memberships.first(where: { $0.conversationId == conversationID })?.folderId,
              folders.contains(where: { $0.id == id }) else { return nil }
        return id
    }
}
