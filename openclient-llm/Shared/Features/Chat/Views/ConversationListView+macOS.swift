//
//  ConversationListView+macOS.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 12/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

nonisolated struct ChatFolderDrag: Codable, Transferable {
    let ids: [UUID]

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: UTType(exportedAs: "com.artcc.openclient-llm.chat-folder-drag",
                                                   conformingTo: .data))
            .visibility(.ownProcess)
    }
}

extension ConversationListView {
    // MARK: - macOS Toolbar

    @ViewBuilder
    func searchScopeControl(_ loaded: ConversationListViewModel.LoadedState) -> some View {
        if !loaded.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           loaded.folderScope != .all || loaded.activeTagFilter != nil {
            Toggle("Search All Chats", isOn: Binding(
                get: { loaded.searchesAllFolders },
                set: { viewModel.send(.filter(.searchAllFolders($0))) }
            ))
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }

    func overflowMenu(_ loaded: ConversationListViewModel.LoadedState) -> some View {
        Menu {
            selectChatsToMoveButton(loaded)
            Divider()
            Button {
                viewModel.send(.exportBackupTapped)
            } label: {
                Label(String(localized: "Export Backup"), systemImage: "archivebox")
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button {
                isShowingBackupImporter = true
            } label: {
                Label(String(localized: "Import Conversations"), systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .help(String(localized: "More"))
        .accessibilityLabel(String(localized: "More"))
        .menuOrder(.fixed)
    }

    var macSearchText: Binding<String> {
        Binding {
            guard case .loaded(let loaded) = viewModel.state else { return "" }
            return loaded.searchQuery
        } set: { query in
            viewModel.send(.searchChanged(query))
            if startGlobalSearch, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                startGlobalSearch = false
                viewModel.send(.filter(.searchAllFolders(true)))
            }
        }
    }

    var macSearchToolbarItem: some View {
        HStack(spacing: 4) {
            if isMacSearchExpanded {
                TextField(macSearchPrompt, text: macSearchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .focused($isMacSearchFocused)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
                    .onAppear {
                        isMacSearchFocused = true
                    }
                    .onSubmit {
                        startGlobalSearch = false
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isMacSearchExpanded = false
                            isMacSearchFocused = false
                        }
                    }
                    .onExitCommand {
                        startGlobalSearch = false
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isMacSearchExpanded = false
                            isMacSearchFocused = false
                            macSearchText.wrappedValue = ""
                        }
                    }
            }
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isMacSearchExpanded.toggle()
                    if !isMacSearchExpanded {
                        startGlobalSearch = false
                        isMacSearchFocused = false
                        macSearchText.wrappedValue = ""
                    }
                }
            } label: {
                Image(systemName: isMacSearchExpanded ? "xmark.circle.fill" : "magnifyingglass")
            }
            .accessibilityLabel(isMacSearchExpanded
                ? String(localized: "Close search")
                : String(localized: "Search conversations"))
            .help(String(localized: "Search"))
        }
        .onAppear {
            if !macSearchText.wrappedValue.isEmpty { isMacSearchExpanded = true }
        }
    }

    private var macSearchPrompt: String {
        guard !startGlobalSearch, case .loaded(let loaded) = viewModel.state,
              loaded.folderScope != .all, !loaded.searchesAllFolders else {
            return String(localized: "Search conversations...")
        }
        return String(localized: "Search in \(loaded.scopeTitle)")
    }
}
#endif
