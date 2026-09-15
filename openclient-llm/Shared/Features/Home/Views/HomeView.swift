//
//  HomeView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct HomeView: View {
    // MARK: - Properties

    let remoteBanner: RemoteBanner?
    let onRemoteBannerDismiss: () -> Void
    let onRemoteBannerAction: () -> Void

    @State private var viewModel = HomeViewModel()
    @State var selectedConversation: Conversation?
    @State var isPrivateChatActive: Bool = false
    @State private var requestedSettingsPresentation: SettingsPresentation?

#if os(macOS)
    @State private var sidebarDestination: SidebarDestination = .chats
    @State private var macSearchRequestID = 0
#endif

#if os(iOS)
    @State var selectedTab: AppTab = .chats
    @State var iPadSearchText = ""
    @State var isSidebarSearchVisible = false
    @State var isSidebarSearchActive = false
    @State var isSidebarSearchFocusRequested = false
    @State var isSidebarSearchFocused = false
#endif

    // MARK: - Init

    init(
        remoteBanner: RemoteBanner? = nil,
        onRemoteBannerDismiss: @escaping () -> Void = {},
        onRemoteBannerAction: @escaping () -> Void = {}
    ) {
        self.remoteBanner = remoteBanner
        self.onRemoteBannerDismiss = onRemoteBannerDismiss
        self.onRemoteBannerAction = onRemoteBannerAction
    }

    // MARK: - View

    var body: some View {
        Group {
#if os(macOS)
            macOSLayout
#else
            iOSLayout
                .safeAreaInset(edge: .top, spacing: 0) {
                    remoteBannerInset
                }
#endif
        }
        .onContinueUserActivity(SpotlightConstants.activityType) { activity in
            guard let idString = activity.userInfo?[SpotlightConstants.activityIdentifierKey] as? String,
                  let id = UUID(uuidString: idString) else { return }
            viewModel.send(.spotlightConversationRequested(id))
        }
        .task {
            viewModel.send(.viewAppeared)
        }
        .onChange(of: viewModel.isPrivateChatRequested) { _, isRequested in
            guard isRequested else { return }
#if os(iOS)
            selectedTab = .chats
#elseif os(macOS)
            sidebarDestination = .chats
#endif
            isPrivateChatActive = true
            viewModel.send(.privateChatRequestConsumed)
        }
        .onChange(of: viewModel.pendingConversation) { _, conversation in
            guard let conversation else { return }
#if os(iOS)
            selectedTab = .chats
#elseif os(macOS)
            sidebarDestination = .chats
#endif
            selectedConversation = conversation
            viewModel.send(.pendingConversationConsumed)
        }
        .task {
            guard let action = viewModel.pendingShortcutAction else { return }
            try? await Task.sleep(for: .milliseconds(300))
            handleShortcutAction(action)
            viewModel.send(.shortcutActionConsumed)
        }
        .onChange(of: viewModel.pendingShortcutAction) { _, action in
            guard let action else { return }
            handleShortcutAction(action)
            viewModel.send(.shortcutActionConsumed)
        }
#if os(iOS)
        .task {
            guard viewModel.hasPendingShare else { return }
            try? await Task.sleep(for: .milliseconds(300))
            viewModel.send(.shareItemReceived)
        }
        .onChange(of: viewModel.hasPendingShare) { _, isPending in
            guard isPending else { return }
            viewModel.send(.shareItemReceived)
        }
#endif
        .task {
            guard viewModel.pendingURLSchemeAction != nil else { return }
            try? await Task.sleep(for: .milliseconds(300))
            viewModel.send(.urlSchemeActionReceived)
        }
        .onChange(of: viewModel.pendingURLSchemeAction) { _, action in
            guard action != nil else { return }
            viewModel.send(.urlSchemeActionReceived)
        }
#if os(macOS)
        .animation(nil, value: remoteBanner?.id)
#else
        .animation(.smooth, value: remoteBanner?.id)
#endif
    }
}

// MARK: - Private

private extension HomeView {
#if os(iOS)
    var iOSLayout: some View {
        TabView(selection: tabSelection) {
            Tab(value: AppTab.chats) {
                chatsTab
                    .modifier(TabBarPlacementObserver(onChange: updateSidebarPlacement))
            } label: {
                Label {
                    Text(String(localized: "Chats"))
                } icon: {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .symbolEffect(.bounce, value: selectedTab)
                }
            }
            Tab(value: AppTab.models) {
                ModelsView()
                    .modifier(TabBarPlacementObserver(onChange: updateSidebarPlacement))
            } label: {
                Label {
                    Text(String(localized: "Models"))
                } icon: {
                    Image(systemName: "brain.head.profile")
                        .symbolEffect(.bounce, value: selectedTab)
                }
            }
            Tab(value: AppTab.settings) {
                SettingsView(requestedPresentation: $requestedSettingsPresentation)
                    .modifier(TabBarPlacementObserver(onChange: updateSidebarPlacement))
            } label: {
                Label {
                    Text(String(localized: "Settings"))
                } icon: {
                    Image(systemName: "gearshape")
                        .symbolEffect(.rotate, value: selectedTab)
                }
            }
            Tab(value: AppTab.search, role: .search) {
                searchTab
                    .modifier(TabBarPlacementObserver(onChange: updateSidebarPlacement))
            } label: {
                Label(String(localized: "Search"), systemImage: "magnifyingglass")
            }
            .hidden(isSidebarSearchVisible)
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewSidebarHeader {
            if UIDevice.current.userInterfaceIdiom == .pad {
                iPadSidebarSearch
            }
        }
        .onChange(of: selectedTab) { _, tab in
            if tab != .chats {
                isSidebarSearchFocusRequested = false
                isSidebarSearchActive = false
                isSidebarSearchFocused = false
            }
        }
        .onChange(of: selectedConversation) { _, conversation in
            if conversation != nil {
                isSidebarSearchFocusRequested = false
                isSidebarSearchActive = false
                isSidebarSearchFocused = false
            }
        }
        .onChange(of: isPrivateChatActive) { _, active in
            if active {
                isSidebarSearchFocusRequested = false
                isSidebarSearchActive = false
                isSidebarSearchFocused = false
            }
        }
    }

    @ViewBuilder
    var chatsTab: some View {
        if isSidebarSearchActive {
            SearchConversationsView(
                searchText: $iPadSearchText,
                showsSearchField: false,
                onConversationSelected: openSearchResult
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    isSidebarSearchFocusRequested = false
                    isSidebarSearchFocused = false
                }
            )
        } else {
            iPhoneChatsLayout
        }
    }

    var iPhoneChatsLayout: some View {
        NavigationStack {
            ConversationListView(activeConversationId: selectedConversation?.id) { conversation in
                selectedConversation = conversation
            } onPrivateChatSelected: {
                isPrivateChatActive = true
            }
            .navigationDestination(item: $selectedConversation) { conversation in
                ChatView(
                    conversation: conversation,
                    shareItem: viewModel.pendingShareItem,
                    urlSchemeText: viewModel.pendingURLSchemeText,
                    onForkCreated: { fork in
                        selectedConversation = fork
                    },
                    onShareItemProcessed: { viewModel.send(.shareItemConsumed) },
                    onURLSchemeTextProcessed: { viewModel.send(.urlSchemeTextConsumed) }
                )
            }
            .navigationDestination(isPresented: $isPrivateChatActive) {
                ChatView(isPrivateChat: true)
            }
        }
    }

#endif

    func handleShortcutAction(_ action: ShortcutAction) {
        switch action {
        case .newChat:
            viewModel.send(.newChatShortcutTriggered)
        case .newPrivateChat:
            viewModel.send(.newPrivateChatShortcutTriggered)
        case .search:
#if os(iOS)
            if isSidebarSearchVisible {
                activateSidebarSearch()
            } else {
                selectedTab = .search
            }
#else
            selectedConversation = nil
            sidebarDestination = .chats
            macSearchRequestID += 1
#endif
        }
    }

#if os(macOS)
    enum SidebarDestination: Hashable {
        case chats
        case models
        case settings
    }

    var macOSLayout: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .top, spacing: 0) {
                    remoteBannerInset
                }
        }
        .onChange(of: sidebarDestination) { _, _ in
            selectedConversation = nil
        }
    }

    var sidebar: some View {
        List(selection: $sidebarDestination) {
            Section {
                Label(String(localized: "Chats"), systemImage: "bubble.left.and.bubble.right")
                    .tag(SidebarDestination.chats)
            }

            Section {
                Label(String(localized: "Models"), systemImage: "brain.head.profile")
                    .tag(SidebarDestination.models)

                Label(String(localized: "Settings"), systemImage: "gearshape")
                    .tag(SidebarDestination.settings)
            }
        }
        .navigationTitle(String(localized: "OpenClient"))
        .navigationSplitViewColumnWidth(180)
    }

    @ViewBuilder
    var detailContent: some View {
        switch sidebarDestination {
        case .chats:
            NavigationStack {
                ConversationListView(
                    activeConversationId: selectedConversation?.id,
                    macSearchRequestID: macSearchRequestID
                ) { conversation in
                    selectedConversation = conversation
                } onPrivateChatSelected: {
                    isPrivateChatActive = true
                }
                .navigationDestination(item: $selectedConversation) { conversation in
                    ChatView(
                        conversation: conversation,
                        shareItem: viewModel.pendingShareItem,
                        urlSchemeText: viewModel.pendingURLSchemeText,
                        onForkCreated: { fork in
                            selectedConversation = fork
                        },
                        onShareItemProcessed: { viewModel.send(.shareItemConsumed) },
                        onURLSchemeTextProcessed: { viewModel.send(.urlSchemeTextConsumed) }
                    )
                }
                .navigationDestination(isPresented: $isPrivateChatActive) {
                    ChatView(isPrivateChat: true)
                }
            }
        case .models:
            ModelsView()
        case .settings:
            SettingsView(requestedPresentation: $requestedSettingsPresentation)
        }
    }
#endif

    @ViewBuilder
    var remoteBannerInset: some View {
        if let remoteBanner {
            RemoteBannerView(
                banner: remoteBanner,
                onDismiss: onRemoteBannerDismiss,
                onAction: handleRemoteBannerAction
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    func handleRemoteBannerAction() {
        guard let action = remoteBanner?.item.action else { return }

        switch action {
        case .close:
            onRemoteBannerDismiss()
        case .openURL:
            onRemoteBannerAction()
        case .feedback:
            routeToSettings(.feedback)
        case .tip:
            routeToSettings(.tipJar)
        }
    }

    func routeToSettings(_ presentation: SettingsPresentation) {
#if os(iOS)
        selectedTab = .settings
#else
        sidebarDestination = .settings
#endif
        requestedSettingsPresentation = presentation
        onRemoteBannerDismiss()
    }
}

// MARK: - Hashable

extension Conversation: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

#Preview {
    HomeView()
}
