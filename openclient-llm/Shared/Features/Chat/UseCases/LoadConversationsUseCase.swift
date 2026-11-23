//
//  LoadConversationsUseCase.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 31/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

protocol LoadConversationsUseCaseProtocol: Sendable {
    func execute() async throws -> [Conversation]
    func executeLocally() async throws -> [Conversation]
    func executeForBackup() async throws -> ConversationBackupSnapshot
}

struct LoadConversationsUseCase: LoadConversationsUseCaseProtocol {
    // MARK: - Properties

    private let repository: ConversationRepositoryProtocol

    // MARK: - Init

    init(repository: ConversationRepositoryProtocol = ConversationRepository()) {
        self.repository = repository
    }

    // MARK: - Execute

    func execute() async throws -> [Conversation] {
        let conversations = try await repository.loadAll()
        return normalizeTags(in: conversations)
    }

    func executeLocally() async throws -> [Conversation] {
        let conversations = try await repository.loadLocal()
        return normalizeTags(in: conversations)
    }

    func executeForBackup() async throws -> ConversationBackupSnapshot {
        let snapshot = try await repository.loadBackupSnapshot()
        return (normalizeTags(in: snapshot.conversations), snapshot.organization)
    }
}

// MARK: - Private

private extension LoadConversationsUseCase {
    func normalizeTags(in conversations: [Conversation]) -> [Conversation] {
        var conversations = conversations
        let colorsByName = conversations.flatMap(\.tags).reduce(into: [String: TagColor]()) { colors, tag in
            if colors[tag.name] == nil {
                colors[tag.name] = tag.color
            }
        }
        for index in conversations.indices {
            conversations[index].tags = conversations[index].tags.map {
                ConversationTag(name: $0.name, color: colorsByName[$0.name] ?? $0.color)
            }
        }
        return conversations
    }
}
