//
//  ConversationListViewModelTests+Backup.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 13/07/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

extension ConversationListViewModelTests {
    // MARK: - Tests — Backup

    func test_send_exportBackupTapped_storesBackupData() async throws {
        // Given
        let backupData = Data("backup".utf8)
        mockLoadConversations.result = .success([])
        mockFetchModels.result = .success([])
        mockExportBackup.result = .success(backupData)
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        // When
        sut.send(.exportBackupTapped)
        await waitUntil {
            guard case .loaded(let loadedState) = self.sut.state else { return false }
            return loadedState.backupData == backupData
        }

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            return XCTFail("Expected loaded state")
        }
        XCTAssertEqual(mockExportBackup.executeCallCount, 1)
        XCTAssertEqual(loadedState.backupData, backupData)
    }

    func test_send_importBackupData_reloadsConversationsAndStoresResult() async throws {
        // Given
        let importedConversation = Conversation(modelId: "gpt-4")
        let importedFolder = ConversationFolder(id: UUID(), name: "Restored", updatedAt: .now)
        let result = ImportConversationsResult(
            importedConversationCount: 1,
            importedFolderCount: 1,
            restoredAttachmentCount: 2,
            skippedAttachmentCount: 0
        )
        mockLoadConversations.result = .success([])
        mockFetchModels.result = .success([])
        mockImportConversations.result = .success(result)
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))
        mockLoadConversations.result = .success([importedConversation])
        mockFolders.snapshot = .init(folders: [importedFolder], memberships: [])

        // When
        let backupData = Data("backup".utf8)
        sut.send(.importBackupData(backupData))
        await waitUntil {
            guard case .loaded(let loadedState) = self.sut.state else { return false }
            return loadedState.importResult == result
        }

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            return XCTFail("Expected loaded state")
        }
        XCTAssertEqual(mockImportConversations.importedData, [backupData])
        XCTAssertEqual(loadedState.conversations, [importedConversation])
        XCTAssertEqual(loadedState.folders, [importedFolder])
        XCTAssertEqual(loadedState.importResult, result)
    }

    func test_send_importBackupData_whenImportFails_setsError() async throws {
        // Given
        mockLoadConversations.result = .success([])
        mockFetchModels.result = .success([])
        mockImportConversations.result = .failure(NSError(domain: "test", code: 1))
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        // When
        sut.send(.importBackupData(Data("invalid".utf8)))
        await waitUntil {
            guard case .loaded(let loadedState) = self.sut.state else { return false }
            return loadedState.errorMessage != nil
        }

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            return XCTFail("Expected loaded state")
        }
        XCTAssertNotNil(loadedState.errorMessage)
        XCTAssertNil(loadedState.importResult)
    }

    func test_send_importResultConsumed_clearsResult() async throws {
        // Given
        mockLoadConversations.result = .success([])
        mockFetchModels.result = .success([])
        mockImportConversations.result = .success(
            ImportConversationsResult(
                importedConversationCount: 1,
                restoredAttachmentCount: 0,
                skippedAttachmentCount: 0
            )
        )
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))
        sut.send(.importBackupData(Data()))
        await waitUntil {
            guard case .loaded(let loadedState) = self.sut.state else { return false }
            return loadedState.importResult != nil
        }

        // When
        sut.send(.importResultConsumed)

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            return XCTFail("Expected loaded state")
        }
        XCTAssertNil(loadedState.importResult)
    }
}
