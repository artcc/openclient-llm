//
//  TwoDeviceConversationFolderCloudTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 23/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class TwoDeviceConversationFolderCloudTests: XCTestCase {
    func test_synchronize_messageAndOfflineMove_preservesBothWithoutChangingChatRevision() async throws {
        // Given
        let harness = try TwoDeviceCloudHarness()
        let original = conversation("Shared")
        try harness.deviceA.writeConversation(original)
        let folder = try await harness.deviceA.folders.create(name: "Work")
        await synchronize(harness.deviceA, harness.deviceB)

        // When: neither device sees the other's edit before reconnecting.
        var edited = original
        edited.updatedAt = original.updatedAt.addingTimeInterval(1)
        edited.messages.append(ChatMessage(role: .user, content: "New message", timestamp: edited.updatedAt))
        try harness.deviceA.writeConversation(edited)
        harness.cloudProvider.setAvailable(false)
        try await harness.deviceB.folders.move([original.id], to: folder.id)
        let movedChats = try await harness.deviceB.conversations.loadLocal()
        XCTAssertEqual(movedChats, [original])
        harness.cloudProvider.setAvailable(true)
        await synchronize(harness.deviceB, harness.deviceA, harness.deviceB)

        // Then
        for device in [harness.deviceA, harness.deviceB] {
            let chats = try await device.conversations.loadLocal()
            let snapshot = try await device.folders.load()
            XCTAssertEqual(chats, [edited])
            XCTAssertEqual(snapshot.folderID(for: original.id), folder.id)
        }
    }

    func test_synchronize_deletedFolderAndOfflineReassignments_onlyLiveDestinationSurvives() async throws {
        // Given
        let harness = try TwoDeviceCloudHarness()
        let leaving = conversation("Leaving")
        let entering = conversation("Entering")
        try harness.deviceA.writeConversation(leaving)
        try harness.deviceA.writeConversation(entering)
        let removed = try await harness.deviceA.folders.create(name: "Removed")
        let kept = try await harness.deviceA.folders.create(name: "Kept")
        try await harness.deviceA.folders.move([leaving.id], to: removed.id)
        try await harness.deviceA.folders.move([entering.id], to: kept.id)
        await synchronize(harness.deviceA, harness.deviceB)

        // When
        try await harness.deviceA.folders.delete(removed.id)
        harness.cloudProvider.setAvailable(false)
        try await harness.deviceB.folders.move([leaving.id], to: kept.id)
        try await harness.deviceB.folders.move([entering.id], to: removed.id)
        harness.cloudProvider.setAvailable(true)
        await synchronize(harness.deviceB, harness.deviceA)

        // Then
        for device in [harness.deviceA, harness.deviceB] {
            let chats = try await device.conversations.loadLocal()
            let snapshot = try await device.folders.load()
            XCTAssertEqual(Set(chats.map(\.id)), [leaving.id, entering.id])
            XCTAssertEqual(snapshot.folders.map(\.id), [kept.id])
            XCTAssertEqual(snapshot.folderID(for: leaving.id), kept.id)
            XCTAssertNil(snapshot.folderID(for: entering.id))
        }
        let cloud = try harness.cloudBytes()
        let localA = try harness.bytes(in: harness.deviceA.documentsURL)
        let localB = try harness.bytes(in: harness.deviceB.documentsURL)
        await synchronize(harness.deviceA, harness.deviceB)
        XCTAssertEqual(try harness.cloudBytes(), cloud)
        XCTAssertEqual(try harness.bytes(in: harness.deviceA.documentsURL), localA)
        XCTAssertEqual(try harness.bytes(in: harness.deviceB.documentsURL), localB)
    }

    func test_deleteAll_emptyFolderFromFastClock_purgePreventsStaleDeviceResurrection() async throws {
        // Given: the newest cloud revision belongs to a folder with no chats.
        let harness = try TwoDeviceCloudHarness()
        let future = Date(timeIntervalSince1970: 4_000_000_000)
        let folder = ConversationFolder(id: UUID(), name: "Empty", updatedAt: future)
        let folderURL = harness.cloudDocumentsURL
            .appendingPathComponent("ConversationFolders/\(folder.id.uuidString).json")
        try FileManager.default.createDirectory(
            at: folderURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try SyncJSONCoding.makeEncoder().encode(folder).write(to: folderURL, options: .atomic)
        await synchronize(harness.deviceA, harness.deviceB)
        let stale = try await harness.deviceB.folders.load()
        XCTAssertEqual(stale.folders, [folder])

        // When
        let deletion = try await harness.deviceA.cloudDataManagement.deleteAll()

        // Then
        XCTAssertTrue(deletion.failedCategories.isEmpty)
        XCTAssertGreaterThanOrEqual(deletion.marker.deletedAt, folder.updatedAt)
        let purged = try await harness.deviceA.folders.load()
        XCTAssertTrue(purged.folders.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folderURL.path))
        await synchronize(harness.deviceB, harness.deviceA)
        let reconciled = try await harness.deviceB.folders.load()
        XCTAssertTrue(reconciled.folders.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folderURL.path))
    }

    func test_synchronize_corruptCloudMembership_blocksConversationUploadUntilRepaired() async throws {
        // Given
        let harness = try TwoDeviceCloudHarness()
        let shared = conversation("Shared")
        try harness.deviceA.writeConversation(shared)
        let folder = try await harness.deviceA.folders.create(name: "Work")
        try await harness.deviceA.folders.move([shared.id], to: folder.id)
        await synchronize(harness.deviceA, harness.deviceB)
        let membershipURL = harness.cloudDocumentsURL
            .appendingPathComponent("ConversationFolderMemberships/\(shared.id.uuidString).json")
        let valid = try Data(contentsOf: membershipURL)
        try Data("invalid json".utf8).write(to: membershipURL, options: .atomic)
        let local = conversation("Local only")
        try harness.deviceB.writeConversation(local)
        let cloudBefore = try harness.cloudBytes()

        // When
        let result = await harness.deviceB.conversations.synchronize()

        // Then
        XCTAssertEqual(result, .failed)
        XCTAssertEqual(try harness.cloudBytes(), cloudBefore)
        let snapshot = try await harness.deviceB.folders.load()
        XCTAssertEqual(snapshot.folderID(for: shared.id), folder.id)
        try valid.write(to: membershipURL, options: .atomic)
        await synchronize(harness.deviceB, harness.deviceA)
        let chats = try await harness.deviceA.conversations.loadLocal()
        XCTAssertEqual(Set(chats.map(\.id)), [shared.id, local.id])
    }

    func test_synchronize_pendingFolderTombstone_preservesStaleFolderUntilDownloadCompletes() async throws {
        // Given
        let harness = try TwoDeviceCloudHarness()
        let folder = try await harness.deviceA.folders.create(name: "Temporary")
        await synchronize(harness.deviceA, harness.deviceB)
        try await harness.deviceA.folders.delete(folder.id)
        let directory = harness.cloudDocumentsURL.appendingPathComponent("ConversationFolderTombstones")
        let marker = directory.appendingPathComponent("\(folder.id.uuidString).json")
        let placeholder = directory.appendingPathComponent(".\(marker.lastPathComponent).icloud")
        try FileManager.default.moveItem(at: marker, to: placeholder)
        let cloudBefore = try harness.cloudBytes()

        // When
        let result = await harness.deviceB.conversations.synchronize()

        // Then
        XCTAssertEqual(result, .pendingDownload)
        XCTAssertEqual(try harness.cloudBytes(), cloudBefore)
        let pending = try await harness.deviceB.folders.load()
        XCTAssertEqual(pending.folders.map(\.id), [folder.id])
        try FileManager.default.moveItem(at: placeholder, to: marker)
        await synchronize(harness.deviceB, harness.deviceA)
        let resolved = try await harness.deviceB.folders.load()
        XCTAssertTrue(resolved.folders.isEmpty)
    }
}

// MARK: - Private

private extension TwoDeviceConversationFolderCloudTests {
    func conversation(_ title: String) -> Conversation {
        let date = Date(timeIntervalSince1970: 1_000)
        return Conversation(title: title, modelId: "model", createdAt: date, updatedAt: date)
    }

    func synchronize(
        _ devices: TwoDeviceCloudHarness.Device...,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for device in devices {
            let result = await device.conversations.synchronize()
            XCTAssertEqual(result, .synchronized, file: file, line: line)
        }
    }
}

private extension TwoDeviceCloudHarness.Device {
    var folders: ConversationFolderRepository { ConversationFolderRepository(repository: conversations) }
}
