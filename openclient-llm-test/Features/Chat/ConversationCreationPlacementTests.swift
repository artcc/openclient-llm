//
//  ConversationCreationPlacementTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 23/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class ConversationCreationPlacementTests: XCTestCase {
    private var directory: URL!
    private var storage: ConversationStorage!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storage = ConversationStorage(cloudSyncManager: MockCloudSyncManager(), baseDirectory: directory)
    }

    override func tearDown() async throws {
        try FileManager.default.removeItem(at: directory)
        storage = nil
        directory = nil
        try await super.tearDown()
    }

    func test_save_existingChatWithStaleDraftPlacement_preservesManualMove() async throws {
        let folderID = UUID()
        let chat = Conversation(modelId: "model")
        _ = try await storage.changeFolders(.create(folderID, "Work"), synchronize: false)
        let persisted = try await save(chat, placement: .folder(folderID))
        let initial = try await storage.loadFolderSnapshot()
        XCTAssertEqual(initial.folderID(for: chat.id), folderID)
        let afterMove = try await storage.changeFolders(.move([chat.id], nil), synchronize: false)

        var edited = persisted
        edited.title = "Updated"
        _ = try await save(edited, base: persisted, placement: .folder(folderID))

        let final = try await storage.loadFolderSnapshot()
        XCTAssertEqual(final, afterMove)
        XCTAssertNil(final.folderID(for: chat.id))
    }

    func test_save_forkAfterParentMoved_inheritsCurrentFolderWithoutEditingParent() async throws {
        let work = UUID()
        let archive = UUID()
        _ = try await storage.changeFolders(.create(work, "Work"), synchronize: false)
        _ = try await storage.changeFolders(.create(archive, "Archive"), synchronize: false)
        let parent = try await save(Conversation(modelId: "model"), placement: .folder(work))
        _ = try await storage.changeFolders(.move([parent.id], archive), synchronize: false)
        let fork = Conversation(modelId: "model", parentConversationId: parent.id)

        _ = try await save(fork, placement: .inheritFrom(parent.id))

        let snapshot = try await storage.loadFolderSnapshot()
        let conversations = try await storage.loadLocal()
        XCTAssertEqual(snapshot.folderID(for: fork.id), archive)
        XCTAssertEqual(conversations.first { $0.id == parent.id }, parent)
    }

    func test_save_deletedDestination_createsUnfiledChat() async throws {
        let folder = UUID()
        _ = try await storage.changeFolders(.create(folder, "Work"), synchronize: false)
        _ = try await storage.changeFolders(.delete(folder), synchronize: false)

        let chat = try await save(Conversation(modelId: "model"), placement: .folder(folder))

        let snapshot = try await storage.loadFolderSnapshot()
        XCTAssertFalse(snapshot.memberships.contains { $0.conversationId == chat.id })
    }

    func test_save_unreadableOrganization_doesNotLeaveChatOrAttachment() async throws {
        let stateURL = directory.appendingPathComponent(ConversationFolderState.fileName)
        let corruptData = Data("invalid".utf8)
        try corruptData.write(to: stateURL)
        let attachment = ChatMessage.Attachment(
            type: .image, fileName: "sample.png", mimeType: "image/png",
            fileRelativePath: "", transientData: Data([1, 2, 3])
        )
        let message = ChatMessage(role: .user, content: "", attachments: [attachment])
        let chat = Conversation(modelId: "model", messages: [message])

        do {
            _ = try await save(chat, placement: .folder(UUID()))
            XCTFail("Expected creation to fail")
        } catch {
            let conversations = try await storage.loadLocal()
            let attachments = try await storage.loadLocalAttachmentFiles()
            XCTAssertTrue(conversations.isEmpty)
            XCTAssertTrue(attachments.isEmpty)
            XCTAssertEqual(try Data(contentsOf: stateURL), corruptData)
        }
    }

    private func save(
        _ chat: Conversation,
        base: Conversation? = nil,
        placement: ConversationCreationPlacement
    ) async throws -> Conversation {
        let saved = try await storage.saveSynchronizing(
            chat, expectedBase: base, synchronize: false, creationPlacement: placement
        )
        return try XCTUnwrap(saved)
    }
}
