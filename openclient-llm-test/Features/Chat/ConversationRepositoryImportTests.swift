//
//  ConversationRepositoryImportTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 23/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class ConversationRepositoryImportTests: XCTestCase {
    func test_importBatch_afterRemoteFuturePurge_keepsChatMembershipAndEmptyFolderOnBothDevices() async throws {
        // Given
        let harness = try TwoDeviceCloudHarness()
        let future = Date(timeIntervalSince1970: 4_000_000_000)
        let stale = Conversation(modelId: "purged", updatedAt: future)
        try harness.deviceA.writeConversation(stale)
        let initialSync = await harness.deviceA.conversations.synchronize()
        XCTAssertEqual(initialSync, .synchronized)
        let purge = try await harness.deviceA.cloudDataManagement.deleteAll()
        XCTAssertTrue(purge.failedCategories.isEmpty)
        XCTAssertGreaterThanOrEqual(purge.marker.deletedAt, future)

        let date = Date(timeIntervalSince1970: 1_000)
        let restored = Conversation(modelId: "restored", createdAt: date, updatedAt: date)
        let folder = ConversationFolder(id: UUID(), name: "Restored folder", updatedAt: date)
        let empty = ConversationFolder(id: UUID(), name: "Empty", updatedAt: date)
        let organization = ConversationFolderSnapshot(folders: [folder, empty], memberships: [
            .init(conversationId: restored.id, folderId: folder.id, updatedAt: date)
        ])

        // When
        _ = try await harness.deviceB.conversations.importBatch([restored], organization: organization)
        let sync = await harness.deviceA.conversations.synchronize()

        // Then
        XCTAssertEqual(sync, .synchronized)
        for device in [harness.deviceA, harness.deviceB] {
            let snapshot = try await device.conversations.loadBackupSnapshot()
            XCTAssertEqual(snapshot.conversations.map(\.id), [restored.id])
            let chat = try XCTUnwrap(snapshot.conversations.first)
            XCTAssertEqual(chat.createdAt, date)
            XCTAssertGreaterThan(chat.updatedAt, purge.marker.deletedAt)
            XCTAssertEqual(Set(snapshot.organization.folders.map(\.id)), [folder.id, empty.id])
            XCTAssertEqual(snapshot.organization.folderID(for: chat.id), folder.id)
            XCTAssertTrue(snapshot.organization.folders.allSatisfy { $0.updatedAt > purge.marker.deletedAt })
            let placement = try XCTUnwrap(snapshot.organization.memberships.first)
            XCTAssertGreaterThan(placement.updatedAt, purge.marker.deletedAt)
        }
    }

    func test_importBatch_newerLocalReset_advancesOnlyRevisionsThatNeedIt() async throws {
        // Given
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = ConversationStorage(cloudSyncManager: MockCloudSyncManager(), baseDirectory: directory)
        try await storage.ensureDirectoryExists()
        let reset = Date(timeIntervalSince1970: 4_000_000_000)
        let newer = reset.addingTimeInterval(10)
        try await storage.saveDeleteAllMarker(.init(deletedAt: reset.addingTimeInterval(-10)))
        try await storage.saveLocalResetMarker(.init(deletedAt: reset))
        let chat = Conversation(modelId: "restored", updatedAt: newer)
        let folder = ConversationFolder(id: UUID(), name: "Older", updatedAt: reset)
        let empty = ConversationFolder(id: UUID(), name: "Newer", updatedAt: newer)
        let organization = ConversationFolderSnapshot(folders: [folder, empty], memberships: [
            .init(conversationId: chat.id, folderId: folder.id, updatedAt: newer)
        ])

        // When
        _ = try await storage.importBatch([chat], organization: organization)

        // Then
        let snapshot = try await storage.loadBackupSnapshot()
        XCTAssertEqual(snapshot.conversations.first?.updatedAt, newer)
        XCTAssertEqual(snapshot.organization.memberships, organization.memberships)
        XCTAssertTrue(snapshot.organization.folders.contains(empty))
        let adjusted = try XCTUnwrap(snapshot.organization.folders.first { $0.id == folder.id })
        XCTAssertGreaterThan(adjusted.updatedAt, reset)
    }

    func test_importBatch_secondAttachmentWriteFails_restoresPriorLibraryAndOrganization() async throws {
        // Given
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = ConversationStorage(cloudSyncManager: MockCloudSyncManager(), baseDirectory: directory)
        let repository = ConversationRepository(settingsManager: MockSettingsManager(), storage: storage)
        let original = Conversation(modelId: "existing")
        try await storage.save(original)
        let folderRepository = ConversationFolderRepository(repository: repository)
        let existingFolder = try await folderRepository.create(name: "Existing")
        try await folderRepository.move([original.id], to: existingFolder.id)
        let before = try await folderRepository.load()
        let folder = ConversationFolder(id: UUID(), name: "New", updatedAt: Date())
        let first = chatWithAttachment()
        let second = chatWithAttachment()
        let organization = ConversationFolderSnapshot(
            folders: [folder], memberships: [.init(conversationId: first.id, folderId: folder.id, updatedAt: Date())]
        )
        let attachmentRoot = directory.appendingPathComponent("Attachments")
        try FileManager.default.createDirectory(at: attachmentRoot, withIntermediateDirectories: true)
        // The first chat can write normally. The second chat's attachment directory cannot be created.
        let blocker = Data("existing non-directory".utf8)
        let blockedDirectory = attachmentRoot.appendingPathComponent(second.id.uuidString)
        try blocker.write(to: blockedDirectory)

        // When
        do {
            _ = try await repository.importBatch([first, second], organization: organization)
            XCTFail("Expected attachment persistence to fail")
        } catch {
            // Then
            let snapshot = try await repository.loadBackupSnapshot()
            XCTAssertEqual(snapshot.organization, before)
            XCTAssertEqual(snapshot.conversations.map(\.id), [original.id])
            XCTAssertEqual(try Data(contentsOf: blockedDirectory), blocker)
            let firstDirectory = attachmentRoot.appendingPathComponent(first.id.uuidString)
            if FileManager.default.fileExists(atPath: firstDirectory.path) {
                XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: firstDirectory.path).isEmpty)
            }
        }
    }

    private func chatWithAttachment() -> Conversation {
        let attachment = ChatMessage.Attachment(
            type: .pdf, fileName: "test.pdf", mimeType: "application/pdf", fileRelativePath: "",
            transientData: Data("attachment".utf8)
        )
        return Conversation(modelId: "model", messages: [.init(role: .user, content: "", attachments: [attachment])])
    }
}
