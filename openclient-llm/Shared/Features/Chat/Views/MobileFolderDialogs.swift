//
//  MobileFolderDialogs.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 23/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

#if os(iOS)
import SwiftUI

enum MobileFolderAction: Equatable {
    case create
    case rename(ConversationFolder)
    case delete(ConversationFolder)

    fileprivate var title: LocalizedStringKey {
        switch self {
        case .create: "New Folder"
        case .rename: "Rename Folder"
        case .delete: "Delete Folder?"
        }
    }
}

extension View {
    func mobileFolderDialogs(
        history: ConversationListViewModel,
        action: Binding<MobileFolderAction?>,
        showsIssues: Bool = true,
        onCreateSubmitted: @escaping () -> Void
    ) -> some View {
        modifier(MobileFolderDialogs(
            history: history, action: action, showsIssues: showsIssues, onCreateSubmitted: onCreateSubmitted
        ))
    }
}

private struct MobileFolderDialogs: ViewModifier {
    let history: ConversationListViewModel
    @Binding var action: MobileFolderAction?
    let showsIssues: Bool
    let onCreateSubmitted: () -> Void

    @State private var draft: String?

    private var loaded: ConversationListViewModel.LoadedState? {
        guard case .loaded(let state) = history.state else { return nil }
        return state
    }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showsIssues, history.folderIssue != nil {
                    ConversationFolderIssueView(viewModel: history)
                        .padding(8)
                        .background(.regularMaterial)
                }
            }
            .alert(action?.title ?? "", isPresented: Binding(
                get: { action != nil },
                set: { if !$0 { action = nil } }
            ), presenting: action) { presented in
                switch presented {
                case .create, .rename:
                    namingFields(presented)
                case .delete(let folder):
                    Button("Delete Folder", role: .destructive) { history.changeFolders(.delete(folder.id)) }
                        .disabled(history.isSavingFolderChange)
                }
                Button("Cancel", role: .cancel) {}
            } message: { presented in
                if case .delete(let folder) = presented {
                    let count = loaded?.folderIDs.values.count { $0 == folder.id } ?? 0
                    Text("Chats in “\(folder.name)”: \(count). Deleting this folder keeps the chats in Unfiled.")
                }
            }
            .onChange(of: action) { draft = nil }
    }

    @ViewBuilder
    private func namingFields(_ presented: MobileFolderAction) -> some View {
        let initialName: String = if case .rename(let folder) = presented { folder.name } else { "" }
        let name = Binding(get: { draft ?? initialName }, set: { draft = $0 })
        TextField("Folder name", text: name)
        Button("Save") {
            let trimmed = name.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            switch presented {
            case .create:
                if history.changeFolders(.create(trimmed)) != nil {
                    // Navigate on the user's action, never after I/O when a different chat might already be open.
                    onCreateSubmitted()
                }
            case .rename(let folder):
                history.changeFolders(.rename(folder.id, trimmed))
            case .delete:
                break
            }
        }
        .disabled(name.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  || history.isSavingFolderChange)
    }
}
#endif
