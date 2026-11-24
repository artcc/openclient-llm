//
//  HomeView+MobileFolders.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 23/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

#if os(iOS)
import SwiftUI

extension HomeView {
    var canOpenFolderDrawer: Bool {
        selectedTab == .chats && !isSidebarSearchVisible && !isSidebarSearchActive
            && selectedConversation == nil && !isPrivateChatActive
    }

    var iPadFolderSidebar: some View {
        IPadFolderSidebar(
            history: mobileHistory,
            active: selectedTab == .chats && !isSidebarSearchActive,
            showsIssues: selectedTab != .chats || isSidebarSearchActive || selectedConversation != nil
                || isPrivateChatActive,
            onSelect: selectMobileFolder,
            onCreateSubmitted: {
                // Adding a folder in the sidebar must not discard an open chat or its draft.
                guard selectedConversation == nil, !isPrivateChatActive else { return }
                selectMobileFolder(mobileHistory.requestedScope)
            }
        )
    }

    func selectMobileFolder(_ scope: ConversationFolderScope) {
        showsFolderDrawer = false
        dismissSidebarSearch()
        isPrivateChatActive = false
        openConversation(nil)
        mobileHistory.setFolderScope(scope)
        selectedTab = .chats
    }
}

private struct IPadFolderSidebar: View {
    let history: ConversationListViewModel
    let active: Bool
    let showsIssues: Bool
    let onSelect: (ConversationFolderScope) -> Void
    let onCreateSubmitted: () -> Void
    @State private var action: MobileFolderAction?

    var body: some View {
        VStack(alignment: .leading) {
            Divider().accessibilityHidden(true)
            MobileFolderRows(
                history: history,
                scope: active ? history.requestedScope : nil,
                includesAllChats: !active || history.requestedScope != .all,
                onSelect: onSelect,
                onAction: { action = $0 }
            )
        }
        .mobileFolderDialogs(
            history: history, action: $action, showsIssues: showsIssues, onCreateSubmitted: onCreateSubmitted
        )
    }
}

struct MobileFolderDrawerPresentation: ViewModifier {
    let history: ConversationListViewModel
    @Binding var isPresented: Bool
    let onSelect: (ConversationFolderScope) -> Void

    func body(content: Content) -> some View {
        content
            .disabled(isPresented)
            .accessibilityHidden(isPresented)
            .overlay(alignment: .leading) {
                ChatFolderDrawer(
                    history: history, isPresented: isPresented, scope: history.requestedScope,
                    onSelect: onSelect, onClose: { isPresented = false }
                )
            }
    }
}
#endif
