//
//  MockConversationRepository.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 31/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation
@testable import openclient_llm

// Safety: Only used within serialized @MainActor test methods.
final class MockConversationRepository: ConversationRepositoryProtocol, @unchecked Sendable {
    // MARK: - Properties

    var conversations: [Conversation] = []
    var saveError: Error?
    var deleteError: Error?
    var deleteAllError: Error?
    var loadError: Error?
    var savedConversations: [Conversation] = []
    var deletedIds: [UUID] = []
    var synchronizeResult: ConversationSyncResult = .synchronized
    var cancelSynchronizationCallCount = 0
    var cancelAndDeleteAllCallCount = 0
    var purgeLocalDataCallCount = 0

    // MARK: - Public

    func loadAll() async throws -> [Conversation] {
        if let loadError { throw loadError }
        return conversations
    }

    func loadLocal() async throws -> [Conversation] {
        if let loadError { throw loadError }
        return conversations
    }

    func loadBackupSnapshot() async throws -> ConversationBackupSnapshot {
        (try await loadLocal(), ConversationFolderSnapshot(folders: [], memberships: []))
    }

    @discardableResult
    func save(
        _ conversation: Conversation,
        expectedBase: Conversation?,
        creationPlacement: ConversationCreationPlacement?
    ) async throws -> Conversation {
        if let saveError { throw saveError }
        savedConversations.append(conversation)
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        } else {
            conversations.append(conversation)
        }
        return conversation
    }

    func importBatch(
        _ conversations: [Conversation],
        organization: ConversationFolderSnapshot
    ) async throws -> [Conversation] {
        if let saveError { throw saveError }
        savedConversations.append(contentsOf: conversations)
        self.conversations.append(contentsOf: conversations)
        return conversations
    }

    func setPinned(_ isPinned: Bool, conversationId: UUID) async throws -> Conversation? {
        if let loadError { throw loadError }
        guard var conversation = conversations.first(where: { $0.id == conversationId }) else { return nil }
        conversation.isPinned = isPinned
        conversation.updatedAt = Date()
        try await save(conversation)
        return conversation
    }

    func rename(_ conversationId: UUID, title: String) async throws -> Conversation? {
        if let loadError { throw loadError }
        guard var conversation = conversations.first(where: { $0.id == conversationId }) else { return nil }
        conversation.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        conversation.updatedAt = Date()
        try await save(conversation)
        return conversation
    }

    func updateTags(_ conversationId: UUID, tags: [ConversationTag]) async throws -> Conversation? {
        if let loadError { throw loadError }
        guard var conversation = conversations.first(where: { $0.id == conversationId }) else { return nil }
        let colorsByName = conversations.flatMap(\.tags).reduce(into: [String: TagColor]()) { colors, tag in
            if colors[tag.name] == nil {
                colors[tag.name] = tag.color
            }
        }
        conversation.tags = tags.map { ConversationTag(name: $0.name, color: colorsByName[$0.name] ?? $0.color) }
        conversation.updatedAt = Date()
        try await save(conversation)
        return conversation
    }

    func delete(_ conversationId: UUID) async throws {
        if let deleteError { throw deleteError }
        deletedIds.append(conversationId)
        conversations.removeAll { $0.id == conversationId }
    }

    func deleteSynchronized(_ conversationId: UUID) async throws {
        try await delete(conversationId)
    }

    func deleteAll() async throws {
        if let deleteAllError { throw deleteAllError }
        conversations.removeAll()
    }

    func synchronize() async -> ConversationSyncResult {
        synchronizeResult
    }

    func cancelSynchronization() async {
        cancelSynchronizationCallCount += 1
    }

    func cancelSynchronizationAndDeleteAll() async throws {
        cancelAndDeleteAllCallCount += 1
        try await deleteAll()
    }

    func purgeLocalData(through marker: CloudPurgeMarker) async throws {
        if let deleteAllError { throw deleteAllError }
        purgeLocalDataCallCount += 1
        conversations.removeAll { $0.updatedAt <= marker.deletedAt }
    }

    func validateLocalReset() async throws {
        if let deleteAllError { throw deleteAllError }
        if let loadError { throw loadError }
    }
}
