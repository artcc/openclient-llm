//
//  ExportBackupUseCaseTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 23/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class ExportBackupUseCaseTests: XCTestCase {
    func test_execute_emptyLibrary_writesValidLegacyBackupWithoutOrganizationKeys() async throws {
        // Given
        let exporter = ExportBackupUseCase(loadConversationsUseCase: MockLoadConversationsUseCase())

        // When
        let data = try await exporter.execute()

        // Then
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 1)
        XCTAssertEqual((json["conversations"] as? [Any])?.count, 0)
        XCTAssertNil(json["folders"])
        XCTAssertNil(json["memberships"])
    }

    func test_execute_fullBackup_isReadableByLegacyReadersAndRestoresFreshOrganization() async throws {
        // Given
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = ConversationStorage(cloudSyncManager: MockCloudSyncManager(), baseDirectory: directory)
        let repository = ConversationRepository(settingsManager: MockSettingsManager(), storage: storage)
        let folderRepository = ConversationFolderRepository(repository: repository)
        let filed = Conversation(title: "Filed", modelId: "model")
        let unfiled = Conversation(title: "Unfiled", modelId: "model")
        try await storage.save(filed)
        try await storage.save(unfiled)
        let full = try await folderRepository.create(name: "Travel")
        let empty = try await folderRepository.create(name: "Empty")
        let deleted = try await folderRepository.create(name: "Deleted")
        try await folderRepository.move([filed.id], to: full.id)
        try await folderRepository.move([unfiled.id], to: deleted.id)
        try await folderRepository.delete(deleted.id)
        let loader = LoadConversationsUseCase(repository: repository)
        let exporter = ExportBackupUseCase(loadConversationsUseCase: loader)
        let saver = MockSaveConversationUseCase()
        let importer = ImportConversationsUseCase(
            saveConversationUseCase: saver,
            loadConversationsUseCase: MockLoadConversationsUseCase()
        )

        // When
        let data = try await exporter.execute()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let legacy = try decoder.decode(LegacyDocument.self, from: data)
        let result = try await importer.execute(data)

        // Then
        XCTAssertEqual(legacy.version, 1)
        XCTAssertEqual(legacy.format, ConversationExportDocument.formatIdentifier)
        XCTAssertEqual(Set(legacy.conversations.map(\.conversation.id)), [filed.id, unfiled.id])
        XCTAssertEqual(result.importedFolderCount, 2)
        XCTAssertEqual(result.importedConversationCount, 2)
        XCTAssertEqual(saver.importBatches.count, 1)
        let organization = try XCTUnwrap(saver.importedOrganizations.first)
        let newFull = try XCTUnwrap(organization.folders.first { $0.name == full.name })
        XCTAssertEqual(Set(organization.folders.map(\.name)), [full.name, empty.name])
        XCTAssertTrue(Set(organization.folders.map(\.id)).isDisjoint(with: [full.id, empty.id]))
        let newFiled = try XCTUnwrap(saver.savedConversations.first { $0.title == filed.title })
        let newUnfiled = try XCTUnwrap(saver.savedConversations.first { $0.title == unfiled.title })
        XCTAssertNotEqual(newFiled.id, filed.id)
        XCTAssertEqual(organization.folderID(for: newFiled.id), newFull.id)
        XCTAssertEqual(Set(organization.memberships.map(\.conversationId)), [newFiled.id, newUnfiled.id])
        XCTAssertNil(organization.folderID(for: newUnfiled.id))
    }

    func test_execute_libraryWithOnlyAnEmptyFolder_restoresAlongsideOriginal() async throws {
        // Given
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = ConversationStorage(cloudSyncManager: MockCloudSyncManager(), baseDirectory: directory)
        let repository = ConversationRepository(settingsManager: MockSettingsManager(), storage: storage)
        let folderRepository = ConversationFolderRepository(repository: repository)
        let original = try await folderRepository.create(name: "Empty")
        let load = LoadConversationsUseCase(repository: repository)
        let backup = try await ExportBackupUseCase(loadConversationsUseCase: load).execute()

        // When
        let result = try await ImportConversationsUseCase(
            saveConversationUseCase: SaveConversationUseCase(repository: repository),
            loadConversationsUseCase: load
        ).execute(backup)

        // Then
        let snapshot = try await repository.loadBackupSnapshot()
        XCTAssertEqual(result.importedConversationCount, 0)
        XCTAssertEqual(result.importedFolderCount, 1)
        XCTAssertTrue(snapshot.conversations.isEmpty)
        XCTAssertEqual(snapshot.organization.folders.map(\.name), [original.name, original.name])
        XCTAssertEqual(Set(snapshot.organization.folders.map(\.id)).count, 2)
        XCTAssertTrue(snapshot.organization.folders.contains { $0.id == original.id })
        XCTAssertTrue(snapshot.organization.memberships.isEmpty)
    }
}

private struct LegacyDocument: Decodable {
    let version: Int
    let format: String
    let exportedAt: Date
    let conversations: [ConversationExportDocument.ExportedConversation]
}
