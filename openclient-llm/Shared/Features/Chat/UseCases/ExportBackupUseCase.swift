//
//  ExportBackupUseCase.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 13/07/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

protocol ExportBackupUseCaseProtocol: Sendable {
    func execute() async throws -> Data
}

struct ExportBackupUseCase: ExportBackupUseCaseProtocol {
    // MARK: - Properties

    private let loadConversationsUseCase: LoadConversationsUseCaseProtocol
    private let exportConversationsUseCase: ExportConversationsUseCaseProtocol

    // MARK: - Init

    init(
        loadConversationsUseCase: LoadConversationsUseCaseProtocol = LoadConversationsUseCase(),
        exportConversationsUseCase: ExportConversationsUseCaseProtocol = ExportConversationsUseCase()
    ) {
        self.loadConversationsUseCase = loadConversationsUseCase
        self.exportConversationsUseCase = exportConversationsUseCase
    }

    // MARK: - Execute

    func execute() async throws -> Data {
        let (conversations, snapshot) = try await loadConversationsUseCase.executeForBackup()
        let conversationIds = Set(conversations.map(\.id))
        let folderIds = Set(snapshot.folders.map(\.id))
        let memberships = snapshot.memberships.compactMap { membership -> ConversationFolderMembership? in
            guard conversationIds.contains(membership.conversationId) else { return nil }
            return ConversationFolderMembership(
                conversationId: membership.conversationId,
                folderId: membership.folderId.flatMap { folderIds.contains($0) ? $0 : nil },
                updatedAt: membership.updatedAt
            )
        }
        return try exportConversationsUseCase.execute(
            conversations,
            organization: ConversationFolderSnapshot(folders: snapshot.folders, memberships: memberships)
        )
    }
}
