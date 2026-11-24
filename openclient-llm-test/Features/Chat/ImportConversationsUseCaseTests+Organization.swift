//
//  ImportConversationsUseCaseTests+Organization.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 23/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

extension ImportConversationsUseCaseTests {
    func test_execute_legacyV1WithoutOrganization_importsUnfiled() async throws {
        // Given
        let id = UUID()
        let data = Data("""
        {
          "version": 1, "format": "com.artcc.openclient-llm.conversations", "exportedAt": "2026-07-13T08:00:00Z",
          "conversations": [{"conversation": {
            "id": "\(id)", "title": "Legacy", "modelId": "model", "messages": [],
            "createdAt": "2026-07-13T08:00:00Z", "updatedAt": "2026-07-13T08:00:00Z"
          }, "attachments": []}]
        }
        """.utf8)

        // When
        let result = try await sut.execute(data)

        // Then
        let chat = try XCTUnwrap(mockSaveConversation.savedConversations.first)
        XCTAssertEqual(chat.title, "Legacy")
        XCTAssertNotEqual(chat.id, id)
        XCTAssertEqual(result.importedFolderCount, 0)
        XCTAssertEqual(mockSaveConversation.importedOrganizations, [.init(folders: [], memberships: [])])
    }

    func test_execute_invalidOrganization_rejectsEntireBatchBeforeSaving() async throws {
        // Given
        let chat = Conversation(modelId: "model")
        let folder = ConversationFolder(id: UUID(), name: "Travel", updatedAt: Date())
        let membership = ConversationFolderMembership(conversationId: chat.id, folderId: folder.id, updatedAt: Date())
        let invalid: [ConversationFolderSnapshot] = [
            .init(folders: [folder, folder], memberships: []),
            .init(folders: [.init(id: UUID(), name: " \n ", updatedAt: Date())], memberships: []),
            .init(folders: [], memberships: [membership]),
            .init(folders: [folder], memberships: [membership, membership]),
            .init(folders: [folder], memberships: [.init(conversationId: UUID(), folderId: nil, updatedAt: Date())])
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        // When / Then
        for snapshot in invalid {
            let document = ConversationExportDocument(
                conversations: [.init(conversation: chat, attachments: [])], organization: snapshot
            )
            let data = try encoder.encode(document)
            do {
                _ = try await sut.execute(data)
                XCTFail("Expected invalid organization to be rejected")
            } catch {
                XCTAssertTrue(mockSaveConversation.importBatches.isEmpty)
                XCTAssertEqual(mockLoadConversations.executeCallCount, 0)
            }
        }
    }
}
