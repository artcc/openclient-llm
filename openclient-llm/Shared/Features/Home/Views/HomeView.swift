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
    @State private var newChatPlacement: (conversationID: UUID, folderID: UUID)?
    @State var isPrivateChatActive: Bool = false
    @State private var requestedSettingsPresentation: SettingsPresentation?

#if os(macOS)
    @State private var macHistory = ConversationListViewModel()
    @State private var sidebarDestination: MacChatSidebar.Destination = .history(.all)
    @State private var macSearchRequested = false
    private var folderScope: ConversationFolderScope {
        if case .history(let scope) = sidebarDestination { return scope }
        return .all
    }
#endif

#if os(iOS)
    @State var mobileHistory = ConversationListViewModel()
    @State var showsFolderDrawer = false
    private var folderScope: ConversationFolderScope { mobileHistory.requestedScope }
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
                .modifier(MobileFolderDrawerPresentation(
                    history: mobileHistory,
                    isPresented: $showsFolderDrawer,
                    onSelect: selectMobileFolder
                ))
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
            showsFolderDrawer = false
            dismissSidebarSearch()
            openConversation(nil)
            selectedTab = .chats
#elseif os(macOS)
            openConversation(nil)
            showMacHistoryForExternalEntry()
#endif
            isPrivateChatActive = true
            viewModel.send(.privateChatRequestConsumed)
        }
        .onChange(of: viewModel.pendingConversation) { _, conversation in
            guard let conversation else { return }
#if os(iOS)
            showsFolderDrawer = false
            dismissSidebarSearch()
            isPrivateChatActive = false
            selectedTab = .chats
#elseif os(macOS)
            isPrivateChatActive = false
            showMacHistoryForExternalEntry()
#endif
            openConversation(conversation)
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
        .animation(.smooth, value: remoteBanner?.id)
    }
}

// MARK: - Private

private extension HomeView {
#if os(iOS)
    var iOSLayout: some View {
        iOSTabs
            .tabViewStyle(.sidebarAdaptable)
            .tabViewSidebarHeader {
                if UIDevice.current.userInterfaceIdiom == .pad { iPadSidebarSearch }
            }
            .tabViewSidebarFooter {
                if UIDevice.current.userInterfaceIdiom == .pad { iPadFolderSidebar }
            }
            .task { mobileHistory.send(.viewAppeared) }
            .onDisappear {
                mobileHistory.onConversationSelected = nil
                mobileHistory.onNewConversation = nil
                mobileHistory.onPrivateChatSelected = nil
            }
            .onChange(of: selectedTab) { _, tab in
                if tab != .chats {
                    showsFolderDrawer = false
                    dismissSidebarSearch()
                }
            }
            .onChange(of: selectedConversation) { _, conversation in
                if conversation != nil {
                    showsFolderDrawer = false
                    dismissSidebarSearch()
                }
            }
            .onChange(of: isPrivateChatActive) { _, active in
                if active {
                    showsFolderDrawer = false
                    dismissSidebarSearch()
                }
            }
    }

    var iOSTabs: some View {
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
    }

    @ViewBuilder
    var chatsTab: some View {
        if isSidebarSearchActive {
            SearchConversationsView(
                searchText: $iPadSearchText,
                showsSearchField: false,
                sidebarFolderHistory: mobileHistory,
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
            ConversationListView(
                viewModel: mobileHistory,
                folderScope: Binding(get: { folderScope }, set: { mobileHistory.setFolderScope($0) }),
                activeConversationId: selectedConversation?.id,
                onShowFolders: canOpenFolderDrawer ? { showsFolderDrawer = true } : nil,
                onNewConversation: openNewConversation,
                onConversationSelected: openConversation,
                onPrivateChatSelected: { isPrivateChatActive = true }
            )
            .navigationDestination(item: $selectedConversation, destination: chatDestination)
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
            showsFolderDrawer = false
            if isSidebarSearchVisible {
                activateSidebarSearch()
            } else {
                selectedTab = .search
            }
#else
            selectedConversation = nil
            isPrivateChatActive = false
            showMacHistoryForExternalEntry()
            macSearchRequested = true
#endif
        }
    }

#if os(macOS)
    var macOSLayout: some View {
        NavigationSplitView {
            MacChatSidebar(
                selection: Binding(get: { sidebarDestination }, set: selectMacDestination),
                history: macHistory,
                showsFolderIssues: selectedConversation != nil || isPrivateChatActive || !isShowingMacHistory
            )
        } detail: {
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .top, spacing: 0) {
                    remoteBannerInset
                }
        }
        .task {
            macHistory.send(.viewAppeared)
        }
        .onChange(of: macHistory.requestedScope) { _, scope in
            if isShowingMacHistory, folderScope != scope {
                sidebarDestination = .history(scope)
            }
        }
    }

    var isShowingMacHistory: Bool {
        if case .history = sidebarDestination { return true }
        return false
    }

    func selectMacDestination(_ destination: MacChatSidebar.Destination) {
        openConversation(nil)
        isPrivateChatActive = false
        sidebarDestination = destination
        if case .history(let scope) = destination {
            macHistory.setFolderScope(scope)
        } else {
            macHistory.moveSelection = nil
        }
    }

    func showMacHistoryForExternalEntry() {
        if !isShowingMacHistory {
            sidebarDestination = .history(.all)
            macHistory.setFolderScope(.all)
        }
    }

    @ViewBuilder
    var detailContent: some View {
        switch sidebarDestination {
        case .history:
            NavigationStack {
                ConversationListView(
                    viewModel: macHistory,
                    folderScope: Binding(get: { folderScope }, set: { selectMacDestination(.history($0)) }),
                    activeConversationId: selectedConversation?.id,
                    macSearchRequest: $macSearchRequested,
                    onNewConversation: openNewConversation,
                    onConversationSelected: openConversation,
                    onPrivateChatSelected: {
                        openConversation(nil)
                        isPrivateChatActive = true
                    }
                )
                .navigationDestination(item: $selectedConversation, destination: chatDestination)
                .navigationDestination(isPresented: $isPrivateChatActive) {
                    ChatView(isPrivateChat: true)
                }
            }
            .focusedSceneValue(\.conversationListViewModel, macHistory)
        case .models:
            ModelsView()
        case .settings:
            SettingsView(requestedPresentation: $requestedSettingsPresentation)
        }
    }
#endif

    func openNewConversation(_ conversation: Conversation) {
#if os(macOS)
        isPrivateChatActive = false
#endif
        if case .folder(let id) = folderScope {
            newChatPlacement = (conversation.id, id)
        } else {
            newChatPlacement = nil
        }
        selectedConversation = conversation
    }

    func chatDestination(_ conversation: Conversation) -> some View {
        ChatView(
            conversation: conversation,
            initialFolderID: newChatPlacement?.conversationID == conversation.id ? newChatPlacement?.folderID : nil,
            shareItem: viewModel.pendingShareItem,
            urlSchemeText: viewModel.pendingURLSchemeText,
            onForkCreated: { fork in
                guard selectedConversation?.id == conversation.id, !isPrivateChatActive else { return }
#if os(iOS)
                guard selectedTab == .chats, !isSidebarSearchActive else { return }
#endif
                openConversation(fork)
            },
            onShareItemProcessed: { viewModel.send(.shareItemConsumed) },
            onURLSchemeTextProcessed: { viewModel.send(.urlSchemeTextConsumed) }
        )
        .id(conversation.id)
    }

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
        selectMacDestination(.settings)
#endif
        requestedSettingsPresentation = presentation
        onRemoteBannerDismiss()
    }
}

extension HomeView {
    func openConversation(_ conversation: Conversation?) {
        newChatPlacement = nil
        selectedConversation = conversation
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
