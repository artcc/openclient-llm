//
//  ConversationListViewModel+Folders.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 23/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

nonisolated enum ConversationFolderScope: Hashable {
    case all
    case unfiled
    case folder(UUID)
}

extension ConversationListViewModel.LoadedState {
    var scopedConversations: [Conversation] {
        switch folderScope {
        case .all: conversations
        case .unfiled: hasLoadedFolders ? conversations.filter { folderIDs[$0.id] == nil } : []
        case .folder(let id): conversations.filter { folderIDs[$0.id] == id }
        }
    }

    func folderName(for conversationID: UUID) -> String? {
        guard let id = folderIDs[conversationID] else { return nil }
        return folders.first { $0.id == id }?.name
    }

    var scopeTitle: String {
        switch folderScope {
        case .all: String(localized: "All Chats")
        case .unfiled: String(localized: "Unfiled")
        case .folder(let id): folders.first { $0.id == id }?.name ?? String(localized: "Folder")
        }
    }
}

extension ConversationListViewModel {
    enum FolderChange {
        case create(String, moving: [UUID] = [])
        case rename(UUID, String)
        case delete(UUID)
        case move([UUID], UUID?)
    }

    enum FolderIssue: Error {
        case loading
        case saving
        case moveAfterCreation

        var message: String {
            switch self {
            case .loading: String(localized: "Couldn’t load folders.")
            case .saving: String(localized: "Couldn’t save the folder change. Check the folder and try again.")
            case .moveAfterCreation:
                String(localized: "The folder was created, but the chats couldn’t be moved. Try moving them again.")
            }
        }
    }

    func setFolderScope(_ scope: ConversationFolderScope) {
        requestedScope = scope
        guard case .loaded(var loaded) = state, loaded.folderScope != scope else { return }
        loaded.folderScope = scope
        loaded.searchesAllFolders = false
        moveSelection = nil
        applySearchFilter(&loaded)
        updateLoadedState(loaded)
    }

    func retryLoadingFolders() {
        Task { await reloadFolders() }
    }

    func activateRow(_ conversation: Conversation) {
        guard let selection = moveSelection else {
            send(.conversationTapped(conversation))
            return
        }
        if selection.contains(conversation.id) {
            moveSelection?.remove(conversation.id)
        } else {
            moveSelection?.insert(conversation.id)
        }
    }

    func reloadFolders() async {
        let id = UUID()
        folderLoadID = id
        do {
            let snapshot = try await folderRepository.load()
            guard folderLoadID == id, case .loaded(var loaded) = state else { return }
            loaded.folders = snapshot.folders.sorted {
                let order = $0.name.localizedStandardCompare($1.name)
                return order == .orderedSame ? $0.id.uuidString < $1.id.uuidString : order == .orderedAscending
            }
            let validIDs = Set(loaded.folders.map(\.id))
            loaded.folderIDs = snapshot.memberships.reduce(into: [:]) { assignments, membership in
                if let folderID = membership.folderId, validIDs.contains(folderID) {
                    assignments[membership.conversationId] = folderID
                }
            }
            loaded.hasLoadedFolders = true
            if case .folder(let folderID) = requestedScope, !validIDs.contains(folderID) {
                requestedScope = .all
                loaded.folderScope = .all
                loaded.activeTagFilter = nil
                loaded.searchesAllFolders = false
                moveSelection = nil
            }
            applySearchFilter(&loaded)
            updateLoadedState(loaded)
            if folderIssue == .loading { folderIssue = nil }
        } catch is CancellationError {
            return
        } catch {
            if folderLoadID == id { folderIssue = .loading }
        }
    }

    @discardableResult
    func changeFolders(_ change: FolderChange) -> Task<Void, Never>? {
        guard !isSavingFolderChange else { return nil }
        isSavingFolderChange = true
        let originalScope = requestedScope
        return Task {
            defer { isSavingFolderChange = false }
            do {
                switch change {
                case .create(let name, let ids):
                    try await createFolder(name: name, moving: ids, originalScope: originalScope)
                case .rename(let id, let name):
                    try await folderRepository.rename(id, name: name)
                case .delete(let id):
                    try await folderRepository.delete(id)
                case .move(let ids, let destination):
                    try await folderRepository.move(ids, to: destination)
                    moveSelection = nil
                }
                folderIssue = nil
                await reloadFolders()
            } catch is CancellationError {
                return
            } catch let issue as FolderIssue {
                await reloadFolders()
                folderIssue = issue
            } catch {
                folderIssue = .saving
            }
        }
    }

    private func createFolder(name: String, moving ids: [UUID], originalScope: ConversationFolderScope) async throws {
        let folder = try await folderRepository.create(name: name)
        guard !ids.isEmpty else {
            if originalScope == requestedScope {
                setFolderScope(.folder(folder.id))
            }
            return
        }
        do {
            try await folderRepository.move(ids, to: folder.id)
            moveSelection = nil
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw FolderIssue.moveAfterCreation
        }
    }
}
