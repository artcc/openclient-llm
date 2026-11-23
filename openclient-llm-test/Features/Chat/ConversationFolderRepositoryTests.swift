//
//  ConversationFolderRepositoryTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 23/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class ConversationFolderRepositoryTests: XCTestCase {
    func test_move_unfileAndDeleteOnDifferentDevices_preservesChatAndDoesNotResurrectFolder() async throws {
        let harness = try TwoDeviceCloudHarness()
        let first = ConversationFolderRepository(repository: harness.deviceA.conversations)
        let second = ConversationFolderRepository(repository: harness.deviceB.conversations)
        let chat = try await harness.deviceA.conversations.save(Conversation(modelId: "model"))
        let url = harness.cloudDocumentsURL.appendingPathComponent("Conversations/\(chat.id.uuidString).json")
        let bytes = try Data(contentsOf: url)
        let folder = try await first.create(name: "  Archive ")
        XCTAssertEqual(folder.name, "Archive")
        try await first.move([chat.id], to: folder.id)
        await harness.deviceB.conversations.synchronize()
        let before = try await second.load()
        XCTAssertEqual(before.folderID(for: chat.id), folder.id)

        harness.cloudProvider.setAvailable(false)
        try await second.rename(folder.id, name: "Offline rename")
        try await first.move([chat.id], to: nil)
        try await first.delete(folder.id)
        harness.cloudProvider.setAvailable(true)
        await harness.deviceA.conversations.synchronize()
        await harness.deviceB.conversations.synchronize()
        await harness.deviceA.conversations.synchronize()

        let afterA = try await first.load()
        let afterB = try await second.load()
        XCTAssertEqual(afterA, afterB)
        XCTAssertTrue(afterA.folders.isEmpty)
        let membership = try XCTUnwrap(afterA.memberships.first { $0.conversationId == chat.id })
        XCTAssertNil(membership.folderId)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        let cloud = try harness.deviceA.cloud.loadConversationSyncSnapshot()
        XCTAssertEqual(cloud.folderState.tombstones.map(\.id), [folder.id])
        XCTAssertEqual(cloud.conversations[chat.id], chat)
    }

    func test_save_branchAfterRemoteMove_inheritsReconciledParent() async throws {
        let harness = try TwoDeviceCloudHarness()
        let first = ConversationFolderRepository(repository: harness.deviceA.conversations)
        let second = ConversationFolderRepository(repository: harness.deviceB.conversations)
        let parent = try await harness.deviceA.conversations.save(Conversation(modelId: "model"))
        let initial = try await first.create(name: "Initial")
        try await first.move([parent.id], to: initial.id)
        await harness.deviceB.conversations.synchronize()
        let destination = try await second.create(name: "Remote")
        try await second.move([parent.id], to: destination.id)

        let fork = try await harness.deviceA.conversations.save(
            Conversation(modelId: "model", parentConversationId: parent.id),
            expectedBase: nil, creationPlacement: .inheritFrom(parent.id)
        )

        let state = try await first.load()
        XCTAssertEqual(state.folderID(for: fork.id), destination.id)
        XCTAssertEqual(state.folderID(for: parent.id), destination.id)
    }

    func test_save_cloudOnlyChat_retryDoesNotReapplyCreationFolder() async throws {
        let harness = try TwoDeviceCloudHarness()
        let first = ConversationFolderRepository(repository: harness.deviceA.conversations)
        let second = ConversationFolderRepository(repository: harness.deviceB.conversations)
        let initial = try await first.create(name: "Initial")
        let destination = try await first.create(name: "Current")
        let chat = try await harness.deviceA.conversations.save(Conversation(modelId: "model"))
        try await first.move([chat.id], to: destination.id)

        _ = try await harness.deviceB.conversations.save(
            chat, expectedBase: nil, creationPlacement: .folder(initial.id)
        )

        let state = try await second.load()
        XCTAssertEqual(state.folderID(for: chat.id), destination.id)
    }

    func test_synchronize_offlineFirstSaves_keepsCloudPlacementAndPublishesGenuinelyNewChat() async throws {
        let harness = try TwoDeviceCloudHarness()
        let first = ConversationFolderRepository(repository: harness.deviceA.conversations)
        let second = ConversationFolderRepository(repository: harness.deviceB.conversations)
        let initial = try await first.create(name: "Draft")
        let current = try await first.create(name: "Cloud")
        await harness.deviceB.conversations.synchronize()
        let existing = try await harness.deviceA.conversations.save(Conversation(modelId: "model"))
        let unfiled = try await harness.deviceA.conversations.save(Conversation(modelId: "model"))
        let manuallyMoved = try await harness.deviceA.conversations.save(Conversation(modelId: "model"))
        try await first.move([existing.id], to: current.id)

        harness.cloudProvider.setAvailable(false)
        let fresh = Conversation(modelId: "model")
        for chat in [existing, unfiled, manuallyMoved, fresh] {
            _ = try await harness.deviceB.conversations.save(
                chat, expectedBase: nil, creationPlacement: .folder(initial.id)
            )
        }
        try await second.move([manuallyMoved.id], to: initial.id)
        let offline = try await second.load()
        XCTAssertEqual(offline.folderID(for: existing.id), initial.id)
        harness.cloudProvider.setAvailable(true)
        let result = await harness.deviceB.conversations.synchronize()
        await harness.deviceA.conversations.synchronize()

        XCTAssertEqual(result, .synchronized)
        let state = try await first.load()
        XCTAssertEqual(state.folderID(for: existing.id), current.id)
        XCTAssertNil(state.folderID(for: unfiled.id))
        XCTAssertEqual(state.folderID(for: manuallyMoved.id), initial.id)
        XCTAssertEqual(state.folderID(for: fresh.id), initial.id)
        let local = try await second.load()
        XCTAssertEqual(local, state)
    }

    func test_move_selectionContainsMissingChat_rejectsEntireMove() async throws {
        let harness = try TwoDeviceCloudHarness()
        let folders = ConversationFolderRepository(repository: harness.deviceA.conversations)
        let chat = try await harness.deviceA.conversations.save(Conversation(modelId: "model"))
        let folder = try await folders.create(name: "Archive")
        let bytes = try harness.cloudBytes()

        do {
            try await folders.move([chat.id, UUID()], to: folder.id)
            XCTFail("Expected stale selection to be rejected")
        } catch CloudSyncError.staleConversationRevision {}

        let state = try await folders.load()
        XCTAssertTrue(state.memberships.isEmpty)
        XCTAssertEqual(try harness.cloudBytes(), bytes)
    }

    func test_synchronize_recreatedChatsWithStaleRemoteMemberships_keepNewPlacement() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cloud = MockCloudSyncManager()
        let storage = ConversationStorage(cloudSyncManager: cloud, baseDirectory: root)
        let folderID = UUID()
        _ = try await storage.changeFolders(.create(folderID, "Restored"), synchronize: false)

        let purgeDate = Date(timeIntervalSince1970: 100)
        let deletionDate = Date(timeIntervalSince1970: 200)
        let purged = Conversation(modelId: "model", updatedAt: purgeDate)
        let deleted = Conversation(modelId: "model", updatedAt: deletionDate)
        try await storage.saveDeleteAllMarker(.init(deletedAt: purgeDate))
        try await storage.saveTombstones([.init(conversationId: deleted.id, deletedAt: deletionDate)])
        cloud.cloudConversations = [purged, deleted]
        cloud.cloudFolderState.memberships = [purged, deleted].map {
            .init(conversationId: $0.id, folderId: nil, updatedAt: $0.updatedAt)
        }
        for var chat in [purged, deleted] {
            chat.updatedAt = Date(timeIntervalSince1970: 300)
            _ = try await storage.saveSynchronizing(
                chat, expectedBase: nil, synchronize: false, creationPlacement: .folder(folderID)
            )
        }

        let result = await storage.synchronize()

        XCTAssertEqual(result, .synchronized)
        let local = try await storage.loadFolderSnapshot()
        for id in [purged.id, deleted.id] {
            XCTAssertEqual(local.folderID(for: id), folderID)
            XCTAssertEqual(cloud.cloudFolderState.snapshot.folderID(for: id), folderID)
        }
    }

    func test_synchronize_equalDivergentMemberships_recoversLoserAndConverges() async throws {
        let harness = try TwoDeviceCloudHarness()
        let chat = try await harness.deviceA.conversations.save(Conversation(modelId: "model"))
        let first = ConversationFolderRepository(repository: harness.deviceA.conversations)
        let folder = try await first.create(name: "A")
        try await first.move([chat.id], to: folder.id)
        await harness.deviceB.conversations.synchronize()
        let stateURL = harness.deviceB.documentsURL.appendingPathComponent(ConversationFolderState.fileName)
        var state = try SyncJSONCoding.makeDecoder().decode(
            ConversationFolderState.self, from: Data(contentsOf: stateURL)
        )
        let previous = try XCTUnwrap(state.memberships.first)
        let competing = ConversationFolderMembership(
            conversationId: chat.id, folderId: nil, updatedAt: previous.updatedAt
        )
        state.memberships = [competing]
        let encoder = SyncJSONCoding.makeEncoder()
        try encoder.encode(state).write(to: stateURL, options: .atomic)

        let result = await harness.deviceB.conversations.synchronize()
        await harness.deviceA.conversations.synchronize()

        XCTAssertEqual(result, .synchronized)
        let winner = try await first.load().memberships.first
        let loser = winner == previous ? competing : previous
        let recovery = harness.deviceB.documentsURL
            .appendingPathComponent("ConversationRecovery/ConversationFolderMemberships")
        XCTAssertTrue(try harness.bytes(in: recovery).values.contains(encoder.encode(loser)))
        let cloudBefore = try harness.cloudBytes()
        await harness.deviceB.conversations.synchronize()
        XCTAssertEqual(try harness.cloudBytes(), cloudBefore)
        XCTAssertEqual(try harness.deviceA.cloud.loadConversationSyncSnapshot().folderState.memberships.first, winner)
    }

    func test_deleteAll_emptyFolderAndOfflineCopy_purgesBothAndAllowsPostBarrierFolder() async throws {
        let harness = try TwoDeviceCloudHarness()
        let first = ConversationFolderRepository(repository: harness.deviceA.conversations)
        let second = ConversationFolderRepository(repository: harness.deviceB.conversations)
        _ = try await first.create(name: "Before")
        let retired = try await first.create(name: "Deleted")
        await harness.deviceB.conversations.synchronize()
        try await first.delete(retired.id)

        let result = try await harness.deviceA.cloudDataManagement.deleteAll()
        XCTAssertTrue(result.failedCategories.isEmpty)
        let cloud = try harness.deviceA.cloud.loadConversationSyncSnapshot()
        XCTAssertEqual(cloud.folderState.tombstones.map(\.id), [retired.id])
        await harness.deviceB.conversations.synchronize()
        let purged = try await second.load()
        XCTAssertTrue(purged.folders.isEmpty)
        let fresh = try await second.create(name: "After")
        XCTAssertGreaterThan(fresh.updatedAt, result.marker.deletedAt)
        await harness.deviceA.conversations.synchronize()

        let after = try await first.load()
        XCTAssertEqual(after.folders, [fresh])
        let bytes = try harness.cloudBytes()
        try await harness.deviceA.conversations.cancelSynchronizationAndDeleteAll()
        let reset = try await first.load()
        XCTAssertTrue(reset.folders.isEmpty)
        XCTAssertEqual(try harness.cloudBytes(), bytes)
    }

    func test_synchronize_pendingOrInvalidFolderInput_doesNotUploadLocalEdits() async throws {
        let harness = try TwoDeviceCloudHarness()
        let first = ConversationFolderRepository(repository: harness.deviceA.conversations)
        let folder = try await first.create(name: "Before")
        harness.cloudProvider.setAvailable(false)
        try await first.rename(folder.id, name: "Local")
        harness.cloudProvider.setAvailable(true)
        let root = harness.cloudDocumentsURL.appendingPathComponent(ConversationFolderState.foldersDirectory)
        let url = root.appendingPathComponent("\(folder.id.uuidString).json")
        let original = try Data(contentsOf: url)
        let placeholder = root.appendingPathComponent(".\(UUID().uuidString).json.icloud")
        try Data().write(to: placeholder)

        let pending = await harness.deviceA.conversations.synchronize()
        XCTAssertEqual(pending, .pendingDownload)
        XCTAssertEqual(try Data(contentsOf: url), original)
        try FileManager.default.removeItem(at: placeholder)
        let damaged = root.appendingPathComponent("\(UUID().uuidString).json")
        try Data("invalid".utf8).write(to: damaged)
        let failed = await harness.deviceA.conversations.synchronize()

        XCTAssertEqual(failed, .failed)
        XCTAssertEqual(try Data(contentsOf: damaged), Data("invalid".utf8))
        XCTAssertEqual(try Data(contentsOf: url), original)
        let local = try await first.load()
        XCTAssertEqual(local.folders.first?.name, "Local")
    }
}
