//
//  ConversationListView+Folders.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 23/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

extension ConversationListView {
    var historyTitle: String {
        guard case .loaded(let loaded) = viewModel.state, loaded.folderScope != .all else {
            return String(localized: "Chats")
        }
        return loaded.scopeTitle
    }

    func folderControls(_ loaded: ConversationListViewModel.LoadedState) -> some View {
        let hasContext = viewModel.moveSelection != nil || viewModel.folderIssue != nil
        return VStack(alignment: .leading, spacing: 4) {
            if let selection = viewModel.moveSelection {
                HStack {
                    Text("\(selection.count) selected")
                        .font(.subheadline)
                    Spacer()
                    moveMenu(ids: Array(selection), loaded: loaded)
                    Button("Cancel") { viewModel.moveSelection = nil }
                }
                .disabled(viewModel.isSavingFolderChange)
            }
            ConversationFolderIssueView(viewModel: viewModel)
        }
        .padding(.horizontal, hasContext ? nil : 0)
        .padding(.vertical, hasContext ? 4 : 0)
        .alert("New Folder", isPresented: $isNamingFolder) {
            TextField("Folder name", text: $folderNameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save", action: saveFolderName)
                .disabled(trimmedFolderName.isEmpty)
        }
    }

    func selectChatsToMoveButton(_ loaded: ConversationListViewModel.LoadedState) -> some View {
        Button("Select Chats to Move", systemImage: "checklist") { viewModel.moveSelection = [] }
            .disabled(viewModel.moveSelection != nil || viewModel.isSavingFolderChange ||
                      !loaded.hasLoadedFolders || loaded.filteredConversations.isEmpty)
    }

    private var trimmedFolderName: String {
        folderNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveFolderName() {
        viewModel.changeFolders(.create(trimmedFolderName, moving: idsForNewFolder))
    }

    private func requestNewFolder(moving ids: [UUID]) {
        idsForNewFolder = ids
        folderNameDraft = ""
        isNamingFolder = true
    }

    func moveMenu(ids: [UUID], loaded: ConversationListViewModel.LoadedState) -> some View {
        let sources = Set(ids.map { loaded.folderIDs[$0] })
        return Menu {
            Button("Unfiled", systemImage: "tray") {
                viewModel.changeFolders(.move(ids, nil))
            }
            .disabled(sources == [nil])
            ForEach(loaded.folders) { folder in
                Button {
                    viewModel.changeFolders(.move(ids, folder.id))
                } label: {
                    Label { Text(verbatim: folder.name) } icon: { Image(systemName: "folder") }
                }
                .disabled(sources == [folder.id])
            }
            Divider()
            Button("New Folder…", systemImage: "folder.badge.plus") { requestNewFolder(moving: ids) }
        } label: {
            Label("Move to Folder", systemImage: "folder")
        }
        .disabled(ids.isEmpty || !loaded.hasLoadedFolders || viewModel.isSavingFolderChange)
    }
}

struct ConversationFolderIssueView: View {
    let viewModel: ConversationListViewModel

    var body: some View {
        if let issue = viewModel.folderIssue {
            HStack {
                Label(issue.message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                Spacer(minLength: 4)
                if issue == .loading {
                    Button("Retry") { viewModel.retryLoadingFolders() }
                } else {
                    Button("Dismiss") { viewModel.folderIssue = nil }
                }
            }
        }
    }
}
