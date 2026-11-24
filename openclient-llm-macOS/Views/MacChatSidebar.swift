//
//  MacChatSidebar.swift
//  openclient-llm-macOS
//
//  Created by Arturo Carretero Calvo on 23/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct MacChatSidebar: View {
    enum Destination: Hashable {
        case history(ConversationFolderScope)
        case models
        case settings
    }

    @Binding var selection: Destination
    let history: ConversationListViewModel
    let showsFolderIssues: Bool

    @State private var isExpanded = true
    @State private var isNamingFolder = false
    @State private var folderToRename: ConversationFolder?
    @State private var folderToDelete: ConversationFolder?
    @State private var name = ""
    @State private var dropTarget: ConversationFolderScope?

    private var loaded: ConversationListViewModel.LoadedState? {
        guard case .loaded(let state) = history.state else { return nil }
        return state
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Chats", systemImage: "bubble.left.and.bubble.right")
                    .tag(Destination.history(.all))
                Label("Models", systemImage: "brain.head.profile").tag(Destination.models)
                Label("Settings", systemImage: "gearshape").tag(Destination.settings)
            }
            Section(isExpanded: $isExpanded) {
                ForEach(loaded?.folders ?? []) { folder in
                    folderRow(folder)
                }
                dropRow(String(localized: "Unfiled"), symbol: "tray", scope: .unfiled)
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                        .padding(.vertical, 5)
                        .accessibilityHidden(true)
                    foldersHeader
                        .padding(.bottom, 5)
                }
            }
        }
        .navigationTitle("OpenClient")
        .navigationSplitViewColumnWidth(180)
        .safeAreaInset(edge: .bottom) {
            if showsFolderIssues, history.folderIssue != nil {
                ConversationFolderIssueView(viewModel: history).padding(8)
            }
        }
        .alert(folderToRename == nil ? String(localized: "New Folder") : String(localized: "Rename Folder"),
               isPresented: $isNamingFolder) {
            TextField("Folder name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Save", action: saveName)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Delete Folder?", isPresented: Binding(
            get: { folderToDelete != nil },
            set: { if !$0 { folderToDelete = nil } }
        ), presenting: folderToDelete) { folder in
            Button("Cancel", role: .cancel) {}
            Button("Delete Folder", role: .destructive) { history.changeFolders(.delete(folder.id)) }
        } message: { folder in
            let count = loaded?.folderIDs.values.count { $0 == folder.id } ?? 0
            Text("Chats in “\(folder.name)”: \(count). Deleting this folder keeps the chats in Unfiled.")
        }
    }
}

private extension MacChatSidebar {
    var foldersHeader: some View {
        HStack {
            Text("Folders")
            Spacer()
            Button {
                folderToRename = nil
                name = ""
                isNamingFolder = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("New Folder")
            .help("New Folder")
            .disabled(loaded?.hasLoadedFolders != true || history.isSavingFolderChange)
        }
    }

    func folderRow(_ folder: ConversationFolder) -> some View {
        dropRow(folder.name, symbol: "folder", scope: .folder(folder.id))
            .contextMenu {
                Button("Rename Folder", systemImage: "pencil") {
                    folderToRename = folder
                    name = folder.name
                    isNamingFolder = true
                }
                Button("Delete Folder", systemImage: "trash", role: .destructive) { folderToDelete = folder }
            }
    }

    func dropRow(_ title: String, symbol: String, scope: ConversationFolderScope) -> some View {
        Label { Text(verbatim: title).lineLimit(1) } icon: { Image(systemName: symbol) }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .help(Text(verbatim: title))
            .background {
                if dropTarget == scope {
                    RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.18))
                }
            }
            .dropDestination(for: ChatFolderDrag.self) { items, _ in
                move(items, to: scope)
            } isTargeted: { targeted in
                if targeted { dropTarget = scope } else if dropTarget == scope { dropTarget = nil }
            }
            .tag(Destination.history(scope))
    }

    func move(_ items: [ChatFolderDrag], to scope: ConversationFolderScope) -> Bool {
        guard let loaded, loaded.hasLoadedFolders, !history.isSavingFolderChange else { return false }
        let destination: UUID?
        switch scope {
        case .all: return false
        case .unfiled: destination = nil
        case .folder(let id):
            guard loaded.folders.contains(where: { $0.id == id }) else { return false }
            destination = id
        }
        let ids = Set(items.flatMap(\.ids))
        guard !ids.isEmpty, ids.isSubset(of: loaded.conversations.map(\.id)),
              ids.contains(where: { loaded.folderIDs[$0] != destination }) else { return false }
        return history.changeFolders(.move(Array(ids), destination)) != nil
    }

    func saveName() {
        if let folderToRename {
            history.changeFolders(.rename(folderToRename.id, name))
        } else {
            isExpanded = true
            selection = .history(loaded?.folderScope ?? .all)
            history.changeFolders(.create(name))
        }
    }
}

#Preview {
    @Previewable @State var selection = MacChatSidebar.Destination.history(.all)
    let folder = ConversationFolder(id: UUID(), name: "Design", updatedAt: .now)
    MacChatSidebar(selection: $selection, history: .init(state: .loaded(.init(
        folders: [folder], hasLoadedFolders: true
    ))), showsFolderIssues: false)
    .frame(width: 180, height: 360)
}
