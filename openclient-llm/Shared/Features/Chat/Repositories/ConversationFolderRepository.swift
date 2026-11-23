//
//  ConversationFolderRepository.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 23/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

protocol ConversationFolderRepositoryProtocol: Sendable {
    func load() async throws -> ConversationFolderSnapshot
    func create(name: String) async throws -> ConversationFolder
    func rename(_ id: UUID, name: String) async throws
    func delete(_ id: UUID) async throws
    func move(_ conversationIDs: [UUID], to folderID: UUID?) async throws
}

nonisolated enum ConversationFolderMutation: Sendable {
    case create(UUID, String)
    case rename(UUID, String)
    case delete(UUID)
    case move(Set<UUID>, UUID?)
}

struct ConversationFolderRepository: ConversationFolderRepositoryProtocol {
    private let repository: ConversationRepository

    init(repository: ConversationRepository = ConversationRepository()) {
        self.repository = repository
    }

    func load() async throws -> ConversationFolderSnapshot {
        try await repository.loadFolderSnapshot()
    }

    func create(name: String) async throws -> ConversationFolder {
        let id = UUID()
        let snapshot = try await repository.changeFolders(.create(id, name))
        guard let folder = snapshot.folders.first(where: { $0.id == id }) else {
            throw CloudSyncError.invalidConversationData
        }
        return folder
    }

    func rename(_ id: UUID, name: String) async throws {
        _ = try await repository.changeFolders(.rename(id, name))
    }

    func delete(_ id: UUID) async throws {
        _ = try await repository.changeFolders(.delete(id))
    }

    func move(_ conversationIDs: [UUID], to folderID: UUID?) async throws {
        _ = try await repository.changeFolders(.move(Set(conversationIDs), folderID))
    }
}
