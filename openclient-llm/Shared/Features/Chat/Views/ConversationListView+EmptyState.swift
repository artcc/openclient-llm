//
//  ConversationListView+EmptyState.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 13/07/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI
import TipKit

extension ConversationListView {
    // MARK: - Empty State

    @ViewBuilder
    func filteredEmptyState(_ loaded: ConversationListViewModel.LoadedState) -> some View {
        if !loaded.hasLoadedFolders, loaded.folderScope != .all {
            if viewModel.folderIssue == .loading {
                ContentUnavailableView("Folders Unavailable", systemImage: "folder.badge.questionmark")
            } else {
                ProgressView("Loading folders…")
            }
        } else if !loaded.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView.search(text: loaded.searchQuery)
        } else if loaded.activeTagFilter != nil {
            ContentUnavailableView {
                Label("No Conversations", systemImage: "tag.slash")
            } actions: {
                Button("Clear Tag Filter") { viewModel.send(.tagFilterChanged(nil)) }
            }
        } else if loaded.folderScope == .all {
            emptyState
        } else {
            ContentUnavailableView {
                Label(loaded.folderScope == .unfiled ? String(localized: "No Unfiled Chats") :
                        String(localized: "Empty Folder"), systemImage: "folder")
            } description: {
                Text("Start a new chat here or choose existing chats to move here.")
            } actions: {
                Button("New Chat", systemImage: "square.and.pencil") { viewModel.send(.newConversationTapped) }
                    .buttonStyle(.glassProminent)
                MoveChatsHereButton(loaded: loaded, viewModel: viewModel, conversationTitle: conversationTitle)
                    .id(loaded.folderScope)
            }
        }
    }

    var emptyState: some View {
        ContentUnavailableView {
            Label(
                String(localized: "No Conversations"),
                systemImage: "bubble.left.and.bubble.right"
            )
        } description: {
            Text(String(localized: "Start a new conversation to begin chatting"))
        } actions: {
            VStack(spacing: 15) {
                Button {
                    viewModel.send(.newConversationTapped)
                } label: {
                    Label(String(localized: "New Chat"), systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)

                Button {
                    AppTips.privateChat.invalidate(reason: .actionPerformed)
                    onPrivateChatSelected()
                } label: {
                    Label(String(localized: "New Private Chat"), systemImage: "lock.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
            .padding(.top, 15)
            .padding(.horizontal)
        }
    }
}

private struct MoveChatsHereButton: View {
    let loaded: ConversationListViewModel.LoadedState
    let viewModel: ConversationListViewModel
    let conversationTitle: (Conversation) -> String
    @State private var isPresented = false

    var body: some View {
        Button("Move Chats Here…", systemImage: "folder") { isPresented = true }
            .disabled(loaded.conversations.isEmpty || viewModel.isSavingFolderChange)
            .sheet(isPresented: $isPresented) {
                MoveChatsHereSheet(
                    loaded: loaded, destinationID: destinationID, conversationTitle: conversationTitle
                ) { ids in
                    if viewModel.changeFolders(.move(ids, destinationID)) != nil {
                        isPresented = false
                    }
                }
            }
    }

    private var destinationID: UUID? {
        if case .folder(let id) = loaded.folderScope { return id }
        return nil
    }
}

private struct MoveChatsHereSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<UUID> = []
    let loaded: ConversationListViewModel.LoadedState
    let destinationID: UUID?
    let conversationTitle: (Conversation) -> String
    let onMove: ([UUID]) -> Void

    var body: some View {
        let candidates = loaded.conversations.filter { loaded.folderIDs[$0.id] != destinationID }
        let selectedIDs = candidates.compactMap { selection.contains($0.id) ? $0.id : nil }
        VStack(alignment: .leading, spacing: 12) {
            Text("Move Chats to \(loaded.scopeTitle)")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            List(candidates) { chat in
                Toggle(isOn: Binding(
                    get: { selection.contains(chat.id) },
                    set: { selected in
                        if selected { selection.insert(chat.id) } else { selection.remove(chat.id) }
                    }
                )) {
                    VStack(alignment: .leading) {
                        Text(verbatim: conversationTitle(chat))
                        Text(verbatim: loaded.folderName(for: chat.id) ?? String(localized: "Unfiled"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
#if os(macOS)
                .toggleStyle(.checkbox)
#endif
            }
            .accessibilityLabel("Chats")
            HStack {
                Text("\(selectedIDs.count) selected")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Move") { onMove(selectedIDs) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedIDs.isEmpty)
            }
        }
        .padding()
#if os(macOS)
        .frame(minWidth: 340, idealWidth: 420, minHeight: 240, idealHeight: 360)
#endif
    }
}

#Preview("Move chats into a folder") {
    let folder = ConversationFolder(id: UUID(), name: "Reading", updatedAt: .now)
    let loaded = ConversationListViewModel.LoadedState(
        conversations: [Conversation(title: "Notes", modelId: "Preview")],
        folderScope: .folder(folder.id), folders: [folder], hasLoadedFolders: true
    )
    MoveChatsHereSheet(loaded: loaded, destinationID: folder.id, conversationTitle: { $0.title }, onMove: { _ in })
}
