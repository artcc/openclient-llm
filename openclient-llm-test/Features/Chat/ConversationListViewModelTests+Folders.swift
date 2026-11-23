//
//  ConversationListViewModelTests+Folders.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 23/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

extension ConversationListViewModelTests {
    func test_send_folderScope_filtersTagsAndPreservesHistoryOrderAndPinnedSection() async throws {
        let folder = ConversationFolder(id: UUID(), name: "Work", updatedAt: .now)
        let older = Conversation(modelId: "", tags: [.init(name: "work", color: .blue)], updatedAt: .distantPast)
        let pinned = Conversation(modelId: "", isPinned: true, updatedAt: .distantPast)
        let latest = Conversation(modelId: "", updatedAt: .now)
        let personal = Conversation(modelId: "", tags: [.init(name: "personal", color: .green)])
        await prepareFolderList([latest, personal, older, pinned], in: folder, members: [older, latest, pinned])

        sut.send(.tagFilterChanged("personal"))
        sut.send(.filter(.scopeChanged(.folder(folder.id))))

        let state = try loadedFolderState()
        XCTAssertNil(state.activeTagFilter)
        XCTAssertEqual(state.scopedTags.map(\.name), ["work"])
        XCTAssertEqual(state.filteredConversations.map(\.id), [latest.id, older.id, pinned.id])
        XCTAssertEqual(state.groupedConversations.flatMap(\.conversations).map(\.id), [pinned.id, latest.id, older.id])
    }

    func test_send_searchAllFolders_preservesScopeTagAndQueryUntilSearchEnds() async throws {
        let folder = ConversationFolder(id: UUID(), name: "Work", updatedAt: .now)
        let work = Conversation(title: "Report", modelId: "", tags: [.init(name: "work", color: .blue)])
        let personal = Conversation(modelId: "", messages: [.init(role: .user, content: "Send report")])
        await prepareFolderList([personal, work], in: folder, members: [work])
        sut.send(.filter(.scopeChanged(.folder(folder.id))))
        sut.send(.tagFilterChanged("work"))
        sut.send(.searchChanged("Report"))
        XCTAssertEqual(try loadedFolderState().filteredConversations.map(\.id), [work.id])

        sut.send(.filter(.searchAllFolders(true)))
        let expanded = try loadedFolderState()
        XCTAssertEqual(Set(expanded.filteredConversations.map(\.id)), Set([work.id, personal.id]))
        XCTAssertEqual(expanded.folderName(for: work.id), "Work")
        XCTAssertNil(expanded.folderName(for: personal.id))
        XCTAssertEqual(expanded.searchQuery, "Report")
        XCTAssertEqual(expanded.folderScope, .folder(folder.id))

        sut.send(.searchChanged(""))
        let restored = try loadedFolderState()
        XCTAssertEqual(restored.activeTagFilter, "work")
        XCTAssertFalse(restored.searchesAllFolders)
        XCTAssertEqual(restored.filteredConversations.map(\.id), [work.id])
    }

    func test_reloadFolders_deletedFolderFallsBackToAllOnlyAfterSuccessfulRead() async throws {
        let folder = ConversationFolder(id: UUID(), name: "Empty", updatedAt: .now)
        let chat = Conversation(modelId: "")
        await prepareFolderList([chat], in: folder, members: [])
        sut.send(.filter(.scopeChanged(.folder(folder.id))))
        mockFolders.failLoad = true

        await sut.reloadFolders()
        XCTAssertEqual(try loadedFolderState().folderScope, .folder(folder.id))
        XCTAssertEqual(sut.requestedScope, .folder(folder.id))
        XCTAssertEqual(sut.folderIssue, .loading)

        mockFolders.failLoad = false
        mockFolders.snapshot = .init(folders: [], memberships: [])
        await sut.reloadFolders()
        XCTAssertEqual(sut.requestedScope, .all)
        XCTAssertNil(sut.folderIssue)
        XCTAssertEqual(try loadedFolderState().filteredConversations.map(\.id), [chat.id])
    }

    func test_changeFolders_bulkMoveRetainsSelectionOnFailureAndRefreshesUnfiledOnSuccess() async throws {
        let folder = ConversationFolder(id: UUID(), name: "Work", updatedAt: .now)
        let chats = [Conversation(modelId: ""), Conversation(modelId: "")]
        let ids = chats.map(\.id)
        await prepareFolderList(chats, in: folder, members: [])
        sut.send(.filter(.scopeChanged(.unfiled)))
        sut.moveSelection = Set(ids)
        mockFolders.failMove = true

        await sut.changeFolders(.move(ids, folder.id))?.value
        XCTAssertEqual(sut.folderIssue, .saving)
        XCTAssertNil(try loadedFolderState().errorMessage)
        XCTAssertEqual(sut.moveSelection, Set(ids))

        mockFolders.failMove = false
        await sut.changeFolders(.move(ids, folder.id))?.value
        let state = try loadedFolderState()
        XCTAssertTrue(state.filteredConversations.isEmpty)
        XCTAssertNil(sut.moveSelection)
        XCTAssertNil(sut.folderIssue)
        XCTAssertEqual(state.conversations, chats)
        XCTAssertTrue(ids.allSatisfy { state.folderName(for: $0) == "Work" })
    }

    func test_send_newConversationUsesDedicatedCallbackAndOpeningEmptyChatDoesNot() async {
        let folder = ConversationFolder(id: UUID(), name: "Work", updatedAt: .now)
        let saved = Conversation(modelId: "")
        await prepareFolderList([saved], in: folder, members: [saved])
        sut.send(.filter(.scopeChanged(.folder(folder.id))))
        var created: [Conversation] = []
        var opened: [Conversation?] = []
        sut.onNewConversation = { created.append($0) }
        sut.onConversationSelected = { opened.append($0) }

        sut.send(.newConversationTapped)
        sut.send(.conversationTapped(saved))

        XCTAssertEqual(created.count, 1)
        XCTAssertNotEqual(created.first?.id, saved.id)
        XCTAssertEqual(opened, [saved])
    }

    func test_changeFolders_newMoveDestinationSurvivesMoveFailureAndCanBeRetried() async throws {
        let source = ConversationFolder(id: UUID(), name: "Work", updatedAt: .now)
        let chat = Conversation(modelId: "")
        await prepareFolderList([chat], in: source, members: [chat])
        sut.send(.filter(.scopeChanged(.folder(source.id))))
        sut.moveSelection = [chat.id]
        mockFolders.failMove = true

        await sut.changeFolders(.create("Archive", moving: [chat.id]))?.value
        let failed = try loadedFolderState()
        let destination = try XCTUnwrap(failed.folders.first { $0.name == "Archive" })
        XCTAssertEqual(sut.folderIssue, .moveAfterCreation)
        XCTAssertEqual(sut.moveSelection, [chat.id])
        XCTAssertEqual(failed.folderName(for: chat.id), "Work")

        mockFolders.failMove = false
        await sut.changeFolders(.move([chat.id], destination.id))?.value
        let moved = try loadedFolderState()
        XCTAssertEqual(moved.folderName(for: chat.id), "Archive")
        XCTAssertEqual(moved.folderScope, .folder(source.id))
        XCTAssertTrue(moved.filteredConversations.isEmpty)
    }

    private func prepareFolderList(_ chats: [Conversation], in folder: ConversationFolder,
                                   members: [Conversation]) async {
        mockFolders.snapshot = .init(folders: [folder], memberships: members.map {
            .init(conversationId: $0.id, folderId: folder.id, updatedAt: .now)
        })
        sut = makeViewModel(state: .loaded(.init(conversations: chats)))
        await sut.reloadFolders()
    }

    private func loadedFolderState() throws -> ConversationListViewModel.LoadedState {
        guard case .loaded(let loaded) = sut.state else { throw CocoaError(.coderValueNotFound) }
        return loaded
    }
}

@MainActor
final class ListFolderStoreDouble: ConversationFolderRepositoryProtocol {
    var snapshot = ConversationFolderSnapshot(folders: [], memberships: [])
    var failLoad = false
    var failMove = false

    func load() async throws -> ConversationFolderSnapshot {
        if failLoad { throw CocoaError(.fileReadUnknown) }
        return snapshot
    }

    func move(_ conversationIDs: [UUID], to folderID: UUID?) async throws {
        if failMove { throw CocoaError(.fileWriteUnknown) }
        let remaining = snapshot.memberships.filter { !conversationIDs.contains($0.conversationId) }
        snapshot = .init(folders: snapshot.folders, memberships: remaining + conversationIDs.map {
            .init(conversationId: $0, folderId: folderID, updatedAt: .now)
        })
    }

    func create(name: String) async throws -> ConversationFolder {
        let folder = ConversationFolder(id: UUID(), name: name, updatedAt: .now)
        snapshot = .init(folders: snapshot.folders + [folder], memberships: snapshot.memberships)
        return folder
    }
    func rename(_ id: UUID, name: String) async throws { throw CocoaError(.featureUnsupported) }
    func delete(_ id: UUID) async throws { throw CocoaError(.featureUnsupported) }
}
