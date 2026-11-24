//
//  CloudSyncManager+DataManagement.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 11/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

extension CloudSyncManager {
    func loadCloudInventory() async -> CloudDataInventory {
        var categories: [CloudDataCategory: CloudInventoryCategoryResult] = [:]
        categories[.conversations] = conversationInventoryResult()
        categories[.profile] = await profileInventoryResult()
        categories[.memory] = await memoryInventoryResult()
        categories[.promptTemplates] = await templateInventoryResult()
        return CloudDataInventory(categories: categories)
    }

    func loadCloudPurgeMarker() async throws -> CloudPurgeMarker? {
        try await readCategory { manager, documentsURL in
            try manager.readPurgeMarker(in: documentsURL)
        }
    }

    func loadCloudPurgeJournal() async throws -> CloudPurgeJournal? {
        try await readCategory { manager, documentsURL in
            try manager.readPurgeJournal(in: documentsURL)
        }
    }

    func deleteCloudData(
        categories: Set<CloudDataCategory>,
        marker proposedMarker: CloudPurgeMarker?
    ) async throws -> CloudDeletionResult {
        try await mutationGate.perform {
            let marker = try await self.resolvePurgeMarker(proposedMarker)
            _ = try await self.resolvePurgeJournal(for: marker)
            var outcomes: [CloudDataCategory: CloudDeletionCategoryOutcome] = [:]
            for category in CloudDataCategory.allCases where categories.contains(category) {
                do {
                    let journal = try await self.loadCloudPurgeJournal()
                    if (journal?.categoryStates[category] ?? .pending) == .pending {
                        try await self.deleteCloudCategory(category, using: marker)
                    }
                    outcomes[category] = .deleted
                } catch {
                    outcomes[category] = .failed(self.inventoryFailure(for: error))
                }
            }
            return CloudDeletionResult(marker: marker, outcomes: outcomes)
        }
    }

    func completeLocalPurgeCleanup(category: CloudDataCategory, marker: CloudPurgeMarker) async throws {
        try await mutationGate.perform {
            try await self.updatePurgeState(.completed, category: category, marker: marker)
        }
    }
}

// MARK: - Inventory

private extension CloudSyncManager {
    func conversationInventoryResult() -> CloudInventoryCategoryResult {
        do {
            let snapshot = try loadConversationSyncSnapshot()
            guard snapshot.attachmentPlaceholders.isEmpty else {
                return .failed(.pendingDownload)
            }
            let referencedKeys = try Set(snapshot.conversations.values.flatMap { conversation in
                try conversation.messages.flatMap(\.attachments).compactMap {
                    try ConversationAttachmentPath.key(for: $0, conversationId: conversation.id)
                }
            })
            guard referencedKeys.isSubset(of: snapshot.attachmentData.keys) else {
                return .failed(.corruptData)
            }
            let storedKeys = Set(snapshot.attachmentData.keys).union(snapshot.attachmentPlaceholders)
            guard storedKeys == referencedKeys,
                  snapshot.attachmentConversationIds.isSubset(of: Set(snapshot.conversations.keys)) else {
                return .failed(.corruptData)
            }
            let attachmentCounts = Dictionary(grouping: referencedKeys, by: \.conversationId).mapValues(\.count)
            let items = snapshot.conversations.values.map {
                CloudConversationInventoryItem(
                    id: $0.id,
                    title: sanitizedInventoryTitle($0.title),
                    updatedAt: $0.updatedAt,
                    attachmentCount: attachmentCounts[$0.id] ?? 0
                )
            }.sorted { $0.id.uuidString < $1.id.uuidString }
            return .available(.conversations(items, folderCount: snapshot.folderState.folders.count))
        } catch {
            return .failed(inventoryFailure(for: error))
        }
    }

    func profileInventoryResult() async -> CloudInventoryCategoryResult {
        do {
            let snapshot = try await loadProfileSyncSnapshot()
            let count: Int
            if case .profile = snapshot.state {
                count = 1
            } else {
                count = 0
            }
            return .available(.profileCount(count))
        } catch {
            return .failed(inventoryFailure(for: error))
        }
    }

    func memoryInventoryResult() async -> CloudInventoryCategoryResult {
        do {
            let snapshot = try await loadMemorySyncSnapshot()
            let items = (snapshot.items ?? []).map {
                CloudMemoryInventoryItem(id: $0.id, content: $0.content, updatedAt: $0.updatedAt)
            }.sorted { $0.id.uuidString < $1.id.uuidString }
            return .available(.memory(items))
        } catch {
            return .failed(inventoryFailure(for: error))
        }
    }

    func templateInventoryResult() async -> CloudInventoryCategoryResult {
        do {
            let snapshot = try await loadTemplatesFromCloud()
            let items = snapshot.templates.filter { !$0.isBuiltIn }.map {
                CloudPromptTemplateInventoryItem(
                    id: $0.id,
                    title: sanitizedInventoryTitle($0.title),
                    updatedAt: $0.updatedAt
                )
            }.sorted { $0.id.uuidString < $1.id.uuidString }
            return .available(.promptTemplates(items))
        } catch {
            return .failed(inventoryFailure(for: error))
        }
    }

    func inventoryFailure(for error: Error) -> CloudInventoryFailure {
        if error is CloudSyncManifest.ValidationError { return .unsupportedSchema }
        guard let cloudError = error as? CloudSyncError else {
            if error is DecodingError { return .corruptData }
            return .fileAccess
        }
        switch cloudError {
        case .containerUnavailable, .containerIdentityChanged:
            return .unavailable
        case .requiredDownloadPending:
            return .pendingDownload
        case .cloudContentChanged, .invalidAttachmentPath, .invalidConversationData, .invalidProfileData:
            return .corruptData
        default:
            return .fileAccess
        }
    }

    func sanitizedInventoryTitle(_ title: String) -> String {
        let visibleTitle = title.unicodeScalars.map {
            CharacterSet.controlCharacters.contains($0) ? " " : String($0)
        }.joined()
        let words = visibleTitle.split(whereSeparator: \Character.isWhitespace)
        let normalized = words.joined(separator: " ")
        let bounded = String(normalized.prefix(100))
        return bounded.isEmpty ? String(localized: "Untitled") : bounded
    }
}

// MARK: - Purge

private extension CloudSyncManager {
    func resolvePurgeMarker(_ proposedMarker: CloudPurgeMarker?) async throws -> CloudPurgeMarker {
        if let proposedMarker {
            let stored = try await loadCloudPurgeMarker()
            guard stored == proposedMarker else { throw CloudSyncError.cloudContentChanged }
            return proposedMarker
        }

        let revisions = try await preflightPurgeRevisions()
        let deletedAt = nextPurgeRevision(after: revisions.max() ?? .distantPast)
        let marker = CloudPurgeMarker(id: UUID(), deletedAt: deletedAt)
        try await mutateCategory { manager, documentsURL in
            let existing = try manager.readPurgeMarker(in: documentsURL)
            guard existing.map({ $0.deletedAt < marker.deletedAt }) ?? true else {
                throw CloudSyncError.cloudContentChanged
            }
            try manager.writeEncoded(marker, to: documentsURL.appendingPathComponent("CloudPurgeMarker.json"))
            guard try manager.readPurgeMarker(in: documentsURL) == marker else {
                throw CloudSyncError.cloudContentChanged
            }
        }
        return marker
    }

    func resolvePurgeJournal(for marker: CloudPurgeMarker) async throws -> CloudPurgeJournal {
        if let journal = try await loadCloudPurgeJournal() {
            if journal.marker == marker { return journal }
            guard journal.marker.deletedAt < marker.deletedAt else {
                throw CloudSyncError.cloudContentChanged
            }
        }
        let journal = CloudPurgeJournal(
            marker: marker,
            categoryStates: Dictionary(uniqueKeysWithValues: CloudDataCategory.allCases.map { ($0, .pending) })
        )
        try await mutateCategory { manager, documentsURL in
            guard try manager.readPurgeMarker(in: documentsURL) == marker,
                  try manager.readPurgeJournal(in: documentsURL)?.marker.deletedAt != marker.deletedAt else {
                throw CloudSyncError.cloudContentChanged
            }
            try manager.writePurgeJournal(journal, in: documentsURL)
        }
        return journal
    }

    func preflightPurgeRevisions() async throws -> [Date] {
        let conversations = try loadConversationSyncSnapshot()
        guard conversations.attachmentPlaceholders.isEmpty else {
            throw CloudSyncError.requiredDownloadPending
        }
        let profile = try await loadProfileSyncSnapshot()
        let memory = try await loadMemorySyncSnapshot()
        let templates = try await loadTemplatesFromCloud()
        var revisions = conversations.conversations.values.map(\.updatedAt)
        revisions += conversations.folderState.revisions
        revisions += conversations.tombstones.map(\.deletedAt)
        revisions += [conversations.deleteAllMarker?.deletedAt].compactMap { $0 }
        switch profile.state {
        case .missing:
            break
        case .profile(let value):
            revisions.append(value.modifiedAt)
        case .deleted(let marker):
            revisions.append(marker.deletedAt)
        }
        revisions += (memory.items ?? []).map(\.updatedAt)
        revisions += memory.deletionMarkers.map(\.deletedAt)
        revisions += templates.rawTemplates.values.map(\.updatedAt)
        revisions += templates.deletionMarkers.values.map(\.deletedAt)
        revisions += [
            conversations.purgeMarker?.deletedAt,
            profile.purgeMarker?.deletedAt,
            memory.purgeMarker?.deletedAt,
            templates.purgeMarker?.deletedAt
        ].compactMap { $0 }
        return revisions
    }

    func deleteCloudCategory(_ category: CloudDataCategory, using marker: CloudPurgeMarker) async throws {
        try await mutateCategory { manager, documentsURL in
            guard try manager.readPurgeMarker(in: documentsURL) == marker else {
                throw CloudSyncError.cloudContentChanged
            }
            switch category {
            case .conversations:
                try manager.purgeConversations(in: documentsURL, marker: marker)
            case .profile:
                try manager.purgeProfile(in: documentsURL, marker: marker)
            case .memory:
                try manager.purgeMemory(in: documentsURL, marker: marker)
            case .promptTemplates:
                try manager.purgeTemplates(in: documentsURL, marker: marker)
            }
            try manager.updatePurgeState(
                .cloudCleanupCompleted,
                category: category,
                marker: marker,
                documentsURL: documentsURL
            )
        }
    }

    func updatePurgeState(
        _ state: CloudPurgeCategoryState,
        category: CloudDataCategory,
        marker: CloudPurgeMarker
    ) async throws {
        try await mutateCategory { manager, documentsURL in
            try manager.updatePurgeState(state, category: category, marker: marker, documentsURL: documentsURL)
        }
    }

    func purgeConversations(in documentsURL: URL, marker: CloudPurgeMarker) throws {
        let previous = try loadConversationFolderState(in: documentsURL)
        var folders = previous
        folders.purge(through: marker.deletedAt)
        let directory = documentsURL.appendingPathComponent("Conversations", isDirectory: true)
        var survivingIds = Set<UUID>()
        if fileManager.fileExists(atPath: directory.path) {
            for url in try categoryContents(of: directory) where url.pathExtension == "json" {
                let conversation = try decode(Conversation.self, at: url)
                if conversation.updatedAt > marker.deletedAt {
                    survivingIds.insert(conversation.id)
                } else {
                    try removeCategoryItemIfPresent(at: url)
                }
            }
        }
        try writeConversationFolderState(folders, replacing: previous, in: documentsURL) {
            guard try readPurgeMarker(in: documentsURL) == marker else { throw CloudSyncError.cloudContentChanged }
        }
        let attachmentsURL = documentsURL.appendingPathComponent("Attachments", isDirectory: true)
        guard fileManager.fileExists(atPath: attachmentsURL.path) else { return }
        for url in try categoryContents(of: attachmentsURL) {
            let folderId = UUID(uuidString: url.lastPathComponent)
            guard folderId.map({ !survivingIds.contains($0) }) ?? true else { continue }
            try removeCategoryItemIfPresent(at: url)
        }
    }

    func purgeProfile(in documentsURL: URL, marker: CloudPurgeMarker) throws {
        let url = documentsURL.appendingPathComponent("UserProfile.json")
        guard let profile = try decodeIfPresent(UserProfile.self, at: url),
              profile.modifiedAt <= marker.deletedAt else { return }
        try removeCategoryItemIfPresent(at: url)
    }

    func purgeMemory(in documentsURL: URL, marker: CloudPurgeMarker) throws {
        let url = documentsURL.appendingPathComponent("Memory.json")
        guard let items = try decodeIfPresent([MemoryItem].self, at: url) else { return }
        try writeMemoryValue(items.filter { $0.updatedAt > marker.deletedAt }, to: url)
    }

    func purgeTemplates(in documentsURL: URL, marker: CloudPurgeMarker) throws {
        let directory = documentsURL.appendingPathComponent("PromptTemplates", isDirectory: true)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        for url in try categoryContents(of: directory) where url.pathExtension == "json" {
            let template = try decode(PromptTemplate.self, at: url)
            guard !template.isBuiltIn, template.updatedAt <= marker.deletedAt else { continue }
            try removeCategoryItemIfPresent(at: url)
        }
    }

    func nextPurgeRevision(after revision: Date) -> Date {
        let floor = max(Date(), revision).timeIntervalSince1970.rounded(.down)
        return Date(timeIntervalSince1970: floor + 1)
    }

    func readPurgeJournal(in documentsURL: URL) throws -> CloudPurgeJournal? {
        try decodeIfPresent(
            CloudPurgeJournal.self,
            at: documentsURL.appendingPathComponent("CloudPurgeJournal.json")
        )
    }
    func writePurgeJournal(_ journal: CloudPurgeJournal, in documentsURL: URL) throws {
        let url = documentsURL.appendingPathComponent("CloudPurgeJournal.json")
        try writeEncoded(journal, to: url)
        guard try readPurgeJournal(in: documentsURL) == journal else {
            throw CloudSyncError.cloudContentChanged
        }
    }

    func updatePurgeState(
        _ state: CloudPurgeCategoryState,
        category: CloudDataCategory,
        marker: CloudPurgeMarker,
        documentsURL: URL
    ) throws {
        guard try readPurgeMarker(in: documentsURL) == marker,
              var journal = try readPurgeJournal(in: documentsURL),
              journal.marker == marker else {
            throw CloudSyncError.cloudContentChanged
        }
        let current = journal.categoryStates[category] ?? .pending
        if current == .completed || current == state { return }
        guard current == .pending || state == .completed else {
            throw CloudSyncError.cloudContentChanged
        }
        journal.categoryStates[category] = state
        try writePurgeJournal(journal, in: documentsURL)
    }
}
