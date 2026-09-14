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
                onConversationSelected: openSearchResult
            )
        } else {
            SearchConversationsView()
        }
    }

    var iPadSidebarSearch: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(String(localized: "Search conversations..."), text: $iPadSearchText)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isSidebarSearchFocused)
                .accessibilityIdentifier("iPadSidebarSearch")
                .onSubmit { isSidebarSearchFocused = false }
            if !iPadSearchText.isEmpty {
                Button {
                    iPadSearchText = ""
                    activateSidebarSearch()
                    isSidebarSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Clear Search"))
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, iPadSearchText.isEmpty ? 12 : 0)
        .frame(minHeight: 44)
        .background(.quaternary, in: .capsule)
        .padding(.vertical, 8)
        .onChange(of: isSidebarSearchFocused) { _, focused in
            if focused { activateSidebarSearch() }
        }
        .onAppear {
            isSidebarSearchVisible = true
            if selectedTab == .search { activateSidebarSearch() }
        }
        .onDisappear {
            isSidebarSearchVisible = false
            isSidebarSearchFocused = false
            if isSidebarSearchActive {
                isSidebarSearchActive = false
                selectedTab = .search
            }
        }
    }

    func activateSidebarSearch() {
        selectedTab = .chats
        isSidebarSearchActive = true
    }

    func openSearchResult(_ conversation: Conversation) {
        isSidebarSearchFocused = false
        isSidebarSearchActive = false
        isPrivateChatActive = false
        selectedConversation = conversation
        selectedTab = .chats
    }
}
#endif
