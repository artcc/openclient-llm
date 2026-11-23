//
//  MobileFolderRows.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 23/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

#if os(iOS)
import SwiftUI

struct MobileFolderRows: View {
    let history: ConversationListViewModel
    let scope: ConversationFolderScope?
    let includesAllChats: Bool
    let onSelect: (ConversationFolderScope) -> Void
    let onAction: (MobileFolderAction) -> Void

    private var loaded: ConversationListViewModel.LoadedState? {
        guard case .loaded(let state) = history.state else { return nil }
        return state
    }

    private var canEdit: Bool {
        loaded?.hasLoadedFolders == true && !history.isSavingFolderChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if includesAllChats {
                scopeButton(Text("All Chats"), symbol: "bubble.left.and.bubble.right", destination: .all)
                Divider().accessibilityHidden(true)
            }
            HStack {
                Text("Folders")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button {
                    onAction(.create)
                } label: {
                    Image(systemName: "plus")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("New Folder")
                .disabled(!canEdit)
            }
            .padding(.leading, 10)
            if loaded?.hasLoadedFolders != true, history.folderIssue == nil {
                ProgressView("Loading folders…")
                    .padding(.horizontal, 10)
            }
            ForEach(loaded?.folders ?? []) { folder in
                HStack(spacing: 0) {
                    scopeButton(Text(verbatim: folder.name), symbol: "folder", destination: .folder(folder.id))
                        .contextMenu { folderActions(folder) }
                    Menu {
                        folderActions(folder)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Actions for \(folder.name)")
                    .disabled(!canEdit)
                }
            }
            scopeButton(Text("Unfiled"), symbol: "tray", destination: .unfiled)
        }
    }

    @ViewBuilder
    private func folderActions(_ folder: ConversationFolder) -> some View {
        Button("Rename Folder", systemImage: "pencil") { onAction(.rename(folder)) }
            .disabled(!canEdit)
        Button("Delete Folder", systemImage: "trash", role: .destructive) { onAction(.delete(folder)) }
            .disabled(!canEdit)
    }

    private func scopeButton(_ title: Text, symbol: String, destination: ConversationFolderScope) -> some View {
        let isSelected = scope == destination
        return Button {
            onSelect(destination)
        } label: {
            HStack {
                Label { title.fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: symbol) }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(minHeight: 44)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.14))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
#endif
