//
//  ConversationStorage+Mutations.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 10/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

// MARK: - Mutations

extension ConversationStorage {
    func saveSynchronizing(
        _ conversation: Conversation,
        expectedBase: Conversation?,
        synchronize: Bool,
        preservePendingBase: Bool = false,
        creationPlacement: ConversationCreationPlacement? = nil
    ) throws -> Conversation? {
        try ensureDirectoryExists()
        let canonicalIncoming = try canonicalConversation(conversation)
        let incoming = canonicalIncoming.conversation
        let expectedBase = try expectedBase.map {
            try canonicalConversation($0).conversation
        }
        let latestLocal = try loadLocalConversation(id: incoming.id).map {
            try canonicalConversation($0).conversation
        }
        try validateLocalSaveBase(expectedBase, latestLocal: latestLocal, conversationId: incoming.id)
        guard let latestLocal else {
            return try saveNewConversation(
                incoming,
                attachmentData: canonicalIncoming.attachmentData,
                synchronize: synchronize && !Task.isCancelled,
                creationPlacement: creationPlacement
            )
        }
        let base = expectedBase ?? latestLocal
        try Task.checkCancellation()
        if preservePendingBase {
            return try saveWithoutCloudIfAllowed(
                incoming,
                base: base,
                latestLocal: latestLocal,
                attachmentData: canonicalIncoming.attachmentData
            )
        }
        guard synchronize else {
            return try saveRebasedLocally(
                incoming,
                base: base,
                latestLocal: latestLocal,
                attachmentData: canonicalIncoming.attachmentData
            )
        }
        guard cloudSyncManager.isCloudAvailable() else {
            return try saveWithoutCloudIfAllowed(
                incoming,
                base: base,
                latestLocal: latestLocal,
                attachmentData: canonicalIncoming.attachmentData
            )
        }
        return try saveAgainstCloud(
            incoming,
            base: base,
            latestLocal: latestLocal,
            attachmentData: canonicalIncoming.attachmentData
        )
    }

    @discardableResult
    func setPinned(
        _ isPinned: Bool,
        conversationId: UUID,
        synchronize: Bool
    ) throws -> Conversation? {
        try mutate(conversationId, synchronize: synchronize) { conversation, _ in
            conversation.isPinned = isPinned
        }
    }

    @discardableResult
    func rename(
        _ conversationId: UUID,
        title: String,
        synchronize: Bool
    ) throws -> Conversation? {
        try mutate(conversationId, synchronize: synchronize) { conversation, _ in
            conversation.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    @discardableResult
    func updateTags(
        _ conversationId: UUID,
        tags: [ConversationTag],
        synchronize: Bool
    ) throws -> Conversation? {
        try mutate(conversationId, synchronize: synchronize) { conversation, allConversations in
            let colorsByName = allConversations.flatMap(\.tags).reduce(into: [String: TagColor]()) { colors, tag in
                if colors[tag.name] == nil {
                    colors[tag.name] = tag.color
                }
            }
            var tagNames = Set<String>()
            conversation.tags = tags.compactMap { tag in
                let name = tag.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, tagNames.insert(name).inserted else { return nil }
                return ConversationTag(name: name, color: colorsByName[name] ?? tag.color)
            }
        }
    }

    func mutateMergedConversation(
        conversationId: UUID?,
        merged: inout [MergedConversation],
        attachmentData: [CloudAttachmentKey: Data] = [:],
        mutation: ((inout Conversation, [Conversation]) throws -> Void)?
    ) throws -> Conversation? {
        guard let conversationId,
              let mutation,
              let index = merged.firstIndex(where: { $0.conversation.id == conversationId }) else {
            return nil
        }
        let original = merged[index]
        var conversation = original.conversation
        try mutation(&conversation, merged.map(\.conversation))
        guard conversation != original.conversation else { return conversation }
        conversation.updatedAt = nextModificationDate(after: original.conversation.updatedAt)
        try preserveForRecovery(original.data, conversationId: conversationId)
        let data = try makeEncoder().encode(conversation)
        let canonicalConversation = try makeDecoder().decode(Conversation.self, from: data)
        merged[index] = MergedConversation(
            conversation: canonicalConversation,
            data: data,
            source: original.source,
            localInlineAttachmentData: original.localInlineAttachmentData.merging(attachmentData) { _, new in new },
            cloudInlineAttachmentData: original.cloudInlineAttachmentData
        )
        return canonicalConversation
    }
}

// MARK: - Private

extension ConversationStorage {
    func saveWithoutCloudIfAllowed(
        _ conversation: Conversation,
        base: Conversation,
        latestLocal: Conversation,
        attachmentData: [CloudAttachmentKey: Data]
    ) throws -> Conversation? {
        let pendingBase = try loadPendingMutationBase(conversationId: conversation.id) ?? base
        var rebased = try rebasedConversation(conversation, base: base, onto: latestLocal)
        guard rebased != latestLocal else { return latestLocal }
        rebased.updatedAt = nextModificationDate(after: latestLocal.updatedAt)
        try persistLocalMutation(
            rebased,
            replacing: latestLocal,
            pendingBase: pendingBase,
            attachmentData: attachmentData
        )
        return try loadLocalConversation(id: rebased.id)
    }

    func saveRebasedLocally(
        _ conversation: Conversation,
        base: Conversation,
        latestLocal: Conversation,
        attachmentData: [CloudAttachmentKey: Data]
    ) throws -> Conversation? {
        var rebased = try rebasedConversation(conversation, base: base, onto: latestLocal)
        guard rebased != latestLocal else { return latestLocal }
        rebased.updatedAt = nextModificationDate(after: latestLocal.updatedAt)
        try persistLocalMutation(
            rebased,
            replacing: latestLocal,
            pendingBase: nil,
            attachmentData: attachmentData
        )
        return try loadLocalConversation(id: rebased.id)
    }

    func saveNewConversation(
        _ conversation: Conversation,
        attachmentData: [CloudAttachmentKey: Data],
        synchronize: Bool,
        creationPlacement: ConversationCreationPlacement?
    ) throws -> Conversation? {
        if let localBarrier = try deletionBarrier(for: conversation.id) {
            guard conversation.updatedAt > localBarrier else {
                throw CloudSyncError.staleConversationRevision
            }
        }
        let snapshot: ConversationCloudSyncSnapshot?
        if synchronize, cloudSyncManager.isCloudAvailable() {
            do {
                snapshot = try cloudSyncManager.loadConversationSyncSnapshot()
            } catch {
                LogManager.error("New conversation cloud synchronization deferred")
                snapshot = nil
            }
        } else {
            snapshot = nil
        }
        if let snapshot {
            try validateSaveBase(conversation, against: snapshot)
        }
        try persistNewLocalConversation(
            conversation, attachmentData: attachmentData,
            creationPlacement: snapshot?.conversations[conversation.id] == nil ? creationPlacement : nil,
            cloud: snapshot
        )
        if let snapshot {
            do {
                try self.synchronize(with: snapshot)
            } catch CloudSyncError.staleConversationRevision {
                throw CloudSyncError.staleConversationRevision
            } catch {
                LogManager.error("New conversation cloud synchronization deferred")
            }
        }
        guard let saved = try loadLocalConversation(id: conversation.id) else {
            throw CloudSyncError.staleConversationRevision
        }
        return saved
    }

    func saveAgainstCloud(
        _ conversation: Conversation,
        base: Conversation,
        latestLocal: Conversation,
        attachmentData: [CloudAttachmentKey: Data]
    ) throws -> Conversation? {
        for attempt in 0..<2 {
            do {
                let snapshot = try cloudSyncManager.loadConversationSyncSnapshot()
                try validateSaveBase(base, against: snapshot)
                let saved = try self.synchronize(
                    with: snapshot,
                    conversationId: conversation.id,
                    mutationAttachmentData: attachmentData
                ) { current, _ in
                    current = try self.rebasedConversation(conversation, base: base, onto: current)
                }
                guard let saved else { throw CloudSyncError.staleConversationRevision }
                return saved
            } catch CloudSyncError.cloudContentChanged where attempt == 0 {
                continue
            } catch CloudSyncError.staleConversationRevision {
                throw CloudSyncError.staleConversationRevision
            } catch {
                return try saveWithoutCloudIfAllowed(
                    conversation,
                    base: base,
                    latestLocal: latestLocal,
                    attachmentData: attachmentData
                )
            }
        }
        return try saveWithoutCloudIfAllowed(
            conversation,
            base: base,
            latestLocal: latestLocal,
            attachmentData: attachmentData
        )
    }

    func validateLocalSaveBase(
        _ expectedBase: Conversation?,
        latestLocal: Conversation?,
        conversationId: UUID
    ) throws {
        guard let expectedBase else { return }
        guard expectedBase.id == conversationId else {
            throw CloudSyncError.staleConversationRevision
        }
        guard latestLocal == nil else { return }
        guard let barrier = try deletionBarrier(for: conversationId) else { return }
        guard expectedBase.updatedAt > barrier else {
            throw CloudSyncError.staleConversationRevision
        }
    }

    func validateSaveBase(
        _ base: Conversation,
        against snapshot: ConversationCloudSyncSnapshot
    ) throws {
        let tombstoneDate = snapshot.tombstones
            .filter { $0.conversationId == base.id }
            .map(\.deletedAt)
            .max()
        let barrier = [tombstoneDate, snapshot.deleteAllMarker?.deletedAt]
            .compactMap { $0 }
            .max()
        if let barrier, base.updatedAt <= barrier {
            throw CloudSyncError.staleConversationRevision
        }
    }

    func canonicalConversation(
        _ conversation: Conversation
    ) throws -> (conversation: Conversation, attachmentData: [CloudAttachmentKey: Data]) {
        var conversation = conversation
        let localAttachmentData = try loadLocalAttachmentFiles()
        let knownConversationIds = Set(try loadLocalConversations().map(\.id))
        let normalizedAttachmentData = try normalizeAttachments(
            in: &conversation,
            context: AttachmentNormalizationContext(
                sourceData: localAttachmentData,
                sourcePlaceholders: [],
                knownConversationIds: knownConversationIds
            )
        )
        let requiredAttachmentKeys = try attachmentKeys(in: [conversation])
        guard requiredAttachmentKeys.allSatisfy({
            normalizedAttachmentData[$0] != nil || localAttachmentData[$0] != nil
        }) else {
            throw CloudSyncError.missingAttachment
        }
        for (key, data) in normalizedAttachmentData {
            if let existing = localAttachmentData[key], existing != data {
                throw CloudSyncError.invalidConversationData
            }
        }
        let attachmentData = normalizedAttachmentData.filter { localAttachmentData[$0.key] == nil }
        let data = try makeEncoder().encode(conversation)
        return (try makeDecoder().decode(Conversation.self, from: data), attachmentData)
    }

    func rebasedConversation(
        _ incoming: Conversation,
        base: Conversation,
        onto current: Conversation
    ) throws -> Conversation {
        try ConversationRebaser.rebase(incoming, base: base, onto: current)
    }

    func mutate(
        _ conversationId: UUID,
        synchronize: Bool,
        mutation: @escaping (inout Conversation, [Conversation]) -> Void
    ) throws -> Conversation? {
        try Task.checkCancellation()
        try ensureDirectoryExists()
        guard synchronize else {
            return try mutateLocalConversation(conversationId, mutation: mutation)
        }
        guard cloudSyncManager.isCloudAvailable() else {
            return try mutatePendingLocalConversation(conversationId, mutation: mutation)
        }
        for attempt in 0..<2 {
            do {
                try Task.checkCancellation()
                let snapshot = try cloudSyncManager.loadConversationSyncSnapshot()
                return try self.synchronize(
                    with: snapshot,
                    conversationId: conversationId,
                    mutation: mutation
                )
            } catch CloudSyncError.cloudContentChanged where attempt == 0 {
                continue
            } catch CloudSyncError.staleConversationRevision {
                throw CloudSyncError.staleConversationRevision
            } catch {
                return try mutatePendingLocalConversation(conversationId, mutation: mutation)
            }
        }
        return try mutatePendingLocalConversation(conversationId, mutation: mutation)
    }

    func mutateLocalConversation(
        _ conversationId: UUID,
        mutation: (inout Conversation, [Conversation]) -> Void
    ) throws -> Conversation? {
        let conversations = try loadLocalConversations()
        guard let storedConversation = conversations.first(where: { $0.id == conversationId }) else { return nil }
        let canonical = try canonicalConversation(storedConversation)
        var conversation = canonical.conversation
        let original = conversation
        mutation(&conversation, conversations)
        let didMutate = conversation != original
        guard didMutate || !canonical.attachmentData.isEmpty else { return conversation }
        if didMutate {
            let barrier = try [conversation.updatedAt, deletionBarrier(for: conversationId)]
                .compactMap { $0 }
                .max()
            conversation.updatedAt = nextModificationDate(after: barrier)
        }
        try persistLocalMutation(
            conversation,
            replacing: original,
            pendingBase: nil,
            attachmentData: canonical.attachmentData
        )
        return try loadLocalConversation(id: conversationId)
    }

    func mutatePendingLocalConversation(
        _ conversationId: UUID,
        mutation: (inout Conversation, [Conversation]) -> Void
    ) throws -> Conversation? {
        let conversations = try loadLocalConversations()
        guard let storedConversation = conversations.first(where: { $0.id == conversationId }) else { return nil }
        let canonical = try canonicalConversation(storedConversation)
        var conversation = canonical.conversation
        let storedPendingBase = try loadPendingMutationBase(conversationId: conversationId)
        let pendingCanonical = try storedPendingBase.map(canonicalConversation)
        let pendingBase = pendingCanonical?.conversation ?? conversation
        var attachmentData = canonical.attachmentData
        if let pendingCanonical {
            for (key, data) in pendingCanonical.attachmentData {
                if let existing = attachmentData[key], existing != data {
                    throw CloudSyncError.invalidConversationData
                }
                attachmentData[key] = data
            }
        }
        let original = conversation
        mutation(&conversation, conversations)
        let didMutate = conversation != original
        let shouldReplacePendingBase = storedPendingBase != nil
            && storedPendingBase != pendingCanonical?.conversation
        guard didMutate || !attachmentData.isEmpty || shouldReplacePendingBase else { return conversation }
        if didMutate {
            conversation.updatedAt = nextModificationDate(after: original.updatedAt)
        }
        try persistLocalMutation(
            conversation,
            replacing: original,
            pendingBase: didMutate ? pendingBase : pendingCanonical?.conversation,
            replacePendingBase: shouldReplacePendingBase,
            attachmentData: attachmentData
        )
        return try loadLocalConversation(id: conversationId)
    }

    func deletionBarrier(for conversationId: UUID) throws -> Date? {
        let tombstoneDate = try loadTombstones()
            .filter { $0.conversationId == conversationId }
            .map(\.deletedAt)
            .max()
        let markerDate = try loadDeleteAllMarker()?.deletedAt
        let localResetDate = try loadLocalResetMarker()?.deletedAt
        return [tombstoneDate, markerDate, localResetDate].compactMap { $0 }.max()
    }

    func nextModificationDate(after date: Date?) -> Date {
        guard let date else { return Date() }
        return max(Date(), date.addingTimeInterval(0.000001))
    }

    func modificationDate(requested: Date, after barrier: Date?) -> Date {
        guard let barrier, requested <= barrier else { return requested }
        return barrier.addingTimeInterval(0.000001)
    }
}
