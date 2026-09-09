//
//  ConversationListView+macOS.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 12/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

#if os(macOS)
import SwiftUI

extension ConversationListView {
    // MARK: - macOS Toolbar

    var overflowMenu: some View {
        Menu {
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

    var macSearchToolbarItem: some View {
        HStack(spacing: 4) {
            if isMacSearchExpanded {
                TextField(String(localized: "Search conversations..."), text: $macSearchText)
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
                    .task(id: macSearchRequestID) {
                        guard macSearchRequestID > 0 else { return }
                        isMacSearchFocused = true
                    }
                    .onChange(of: macSearchText) { _, newValue in
                        viewModel.send(.searchChanged(newValue))
                    }
                    .onSubmit {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isMacSearchExpanded = false
                            isMacSearchFocused = false
                        }
                    }
                    .onExitCommand {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isMacSearchExpanded = false
                            isMacSearchFocused = false
                            macSearchText = ""
                            viewModel.send(.searchChanged(""))
                        }
                    }
            }
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isMacSearchExpanded.toggle()
                    if !isMacSearchExpanded {
                        isMacSearchFocused = false
                        macSearchText = ""
                        viewModel.send(.searchChanged(""))
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
    }
}
#endif
