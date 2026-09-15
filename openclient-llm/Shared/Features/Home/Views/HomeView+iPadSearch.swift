//
//  HomeView+iPadSearch.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 14/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

#if os(iOS)
extension HomeView {
    enum AppTab: Hashable {
        case chats
        case models
        case settings
        case search
    }

    var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { tab in
                // Switching to results can write the Chats selection back before its view appears.
                guard !isSidebarSearchFocusRequested || tab != .chats else { return }
                isSidebarSearchFocusRequested = false
                isSidebarSearchFocused = false
                isSidebarSearchActive = false
                selectedTab = tab
            }
        )
    }

    @ViewBuilder
    var searchTab: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            SearchConversationsView(
                searchText: $iPadSearchText,
                isSearchActive: selectedTab == .search && !isSidebarSearchVisible,
                onConversationSelected: openSearchResult
            )
        } else {
            SearchConversationsView()
        }
    }

    var iPadSidebarSearch: some View {
        SidebarSearchField(
            text: $iPadSearchText,
            isFocused: $isSidebarSearchFocused,
            focusRequested: $isSidebarSearchFocusRequested,
            onActivated: activateSidebarSearch
        )
        .padding(.horizontal, -16)
        .padding(.vertical, 8)
    }

    func activateSidebarSearch() {
        guard !isSidebarSearchActive else {
            isSidebarSearchFocused = true
            return
        }
        isSidebarSearchFocusRequested = true
        selectedTab = .chats
        isSidebarSearchActive = true
        isSidebarSearchFocused = true
    }

    func updateSidebarPlacement(_ placement: TabBarPlacement) {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        let showsSidebar = placement == .sidebar
        guard showsSidebar != isSidebarSearchVisible else { return }
        isSidebarSearchVisible = showsSidebar
        if showsSidebar {
            if selectedTab == .search { activateSidebarSearch() }
        } else {
            isSidebarSearchFocusRequested = false
            isSidebarSearchFocused = false
            if isSidebarSearchActive {
                isSidebarSearchActive = false
                selectedTab = .search
            }
        }
    }

    func openSearchResult(_ conversation: Conversation) {
        isSidebarSearchFocusRequested = false
        isSidebarSearchFocused = false
        isSidebarSearchActive = false
        isPrivateChatActive = false
        selectedConversation = conversation
        selectedTab = .chats
    }
}
#endif
