//
//  ConversationListView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 31/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI
import TipKit
import UniformTypeIdentifiers

struct ConversationListView: View {
    // MARK: - Properties

    @Environment(\.scenePhase) private var scenePhase
    @State private var hasBeenActive = false
    @State private var didEnterBackground = false

    @State var viewModel = ConversationListViewModel()
    @State private var editingTagsConversation: Conversation?
    @State private var conversationToDelete: Conversation?
    @State private var renamingConversation: Conversation?
    @State private var renameText: String = ""
    @State var isShowingBackupImporter = false
    @State private var isShowingBackupExporter = false
    @State private var backupFileDocument: ConversationBackupFileDocument?
    let settingsManager: SettingsManagerProtocol = SettingsManager()
    private let appReviewManager: AppReviewManagerProtocol = AppReviewManager()

#if os(macOS)
    @State var isMacSearchExpanded = false
    @State var macSearchText = ""
    @FocusState var isMacSearchFocused: Bool
#endif

    var activeConversationId: UUID?
#if os(macOS)
    var macSearchRequestID = 0
#endif
    let onConversationSelected: (Conversation?) -> Void
    let onPrivateChatSelected: () -> Void

    // MARK: - View

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView()
                    .accessibilityLabel(String(localized: "Loading conversations..."))
                    .tint(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let loadedState):
                loadedView(loadedState)
            }
        }
        .navigationTitle(String(localized: "Chats"))
#if os(macOS)
        .focusedSceneValue(\.newChatAction) {
            viewModel.send(.newConversationTapped)
        }
        .focusedSceneValue(\.newPrivateChatAction) {
            viewModel.send(.newPrivateConversationTapped)
        }
        .task(id: macSearchRequestID) {
            guard macSearchRequestID > 0 else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isMacSearchExpanded = true
            }
        }
#endif
        .task {
            viewModel.onConversationSelected = onConversationSelected
            viewModel.onPrivateChatSelected = onPrivateChatSelected
            viewModel.send(.viewAppeared)
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Reload when the app comes back to the foreground so iCloud-synced
            // conversations from other devices are picked up automatically.
            if newPhase == .active, hasBeenActive, didEnterBackground {
                didEnterBackground = false
                viewModel.refresh()
            } else if newPhase == .active {
                hasBeenActive = true
                didEnterBackground = false
            } else if hasBeenActive, newPhase == .inactive || newPhase == .background {
                didEnterBackground = true
            }
        }
        .sheet(item: $editingTagsConversation) { conversation in
            ConversationTagsView(
                conversationTitle: conversationTitle(conversation),
                existingTags: conversation.tags,
                availableTags: availableTags
            ) { tags in
                viewModel.send(.tagsUpdated(conversation.id, tags))
            }
        }
        .alert(
            String(localized: "Rename Conversation"),
            isPresented: Binding(
                get: { renamingConversation != nil },
                set: { if !$0 { renamingConversation = nil } }
            )
        ) {
            TextField(String(localized: "Conversation name"), text: $renameText)
            Button(String(localized: "Cancel"), role: .cancel) {
                renamingConversation = nil
            }
            Button(String(localized: "Save")) {
                if let conversation = renamingConversation {
                    viewModel.send(.titleEdited(conversation.id, renameText))
                    renamingConversation = nil
                }
            }
        } message: {
            Text(String(localized: "Enter a new name for this conversation."))
        }
        .alert(
            String(localized: "Delete Conversation"),
            isPresented: Binding(
                get: { conversationToDelete != nil },
                set: { if !$0 { conversationToDelete = nil } }
            )
        ) {
            Button(String(localized: "Cancel"), role: .cancel) {
                conversationToDelete = nil
            }
            Button(String(localized: "Delete"), role: .destructive) {
                if let conversation = conversationToDelete {
                    viewModel.send(.deleteConversation(conversation.id))
                    conversationToDelete = nil
                }
            }
        } message: {
            Text(String(localized: "Are you sure you want to delete this conversation? This action cannot be undone."))
        }
        .alert(
            String(localized: "Import Complete"),
            isPresented: Binding(
                get: { importResult != nil },
                set: { if !$0 { consumeImportResult() } }
            )
        ) {
            Button(String(localized: "OK")) {
                consumeImportResult()
            }
        } message: {
            Text(importResultMessage)
        }
        .alert(
            String(localized: "Backup Error"),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { viewModel.send(.errorMessageConsumed) } }
            )
        ) {
            Button(String(localized: "OK")) {
                viewModel.send(.errorMessageConsumed)
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .fileImporter(
            isPresented: $isShowingBackupImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: importBackup
        )
        .fileExporter(
            isPresented: $isShowingBackupExporter,
            document: backupFileDocument,
            contentType: .json,
            defaultFilename: "OpenClient-backup"
        ) { result in
            switch result {
            case .success:
                appReviewManager.requestReview()
            case .failure(let error):
                if !isUserCancellation(error) {
                    viewModel.send(.backupExportWriteFailed)
                }
            }
            backupFileDocument = nil
        }
        .onChange(of: backupData) { _, data in
            guard let data else { return }
            backupFileDocument = ConversationBackupFileDocument(data: data)
            isShowingBackupExporter = true
            viewModel.send(.backupDataConsumed)
        }
    }
}

// MARK: - Private

private extension ConversationListView {
    func consumeImportResult() {
        guard importResult != nil else { return }
        viewModel.send(.importResultConsumed)
        appReviewManager.requestReview()
    }

    var availableTags: [ConversationTag] {
        guard case .loaded(let loadedState) = viewModel.state else { return [] }
        return loadedState.allTags
    }

    func loadedView(_ loadedState: ConversationListViewModel.LoadedState) -> some View {
        Group {
            if loadedState.conversations.isEmpty {
                emptyState
            } else if loadedState.filteredConversations.isEmpty {
                noTagResults
            } else {
                conversationList(loadedState)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                newChatToolbarMenu
            }
#if os(macOS)
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.send(.refreshTapped)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel(String(localized: "Refresh"))
            }
            ToolbarItem(placement: .primaryAction) {
                macSearchToolbarItem
            }
            ToolbarItem(placement: .primaryAction) {
                overflowMenu
            }
#endif
#if os(iOS)
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    viewModel.send(.exportBackupTapped)
                } label: {
                    Label(String(localized: "Export Backup"), systemImage: "archivebox")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    isShowingBackupImporter = true
                } label: {
                    Label(String(localized: "Import Conversations"), systemImage: "square.and.arrow.down")
                }
            }
#endif
        }
        .onChange(of: loadedState.conversations.count, initial: true) { _, count in
            updateMemoryTipEligibility(conversationCount: count)
        }
    }

    var noTagResults: some View {
        ContentUnavailableView {
            Label(
                String(localized: "No Conversations"),
                systemImage: "tag.slash"
            )
        } description: {
            Text(String(localized: "No conversations found with the selected tag"))
        }
    }

    func conversationList(_ loadedState: ConversationListViewModel.LoadedState) -> some View {
        List {
            if !loadedState.allTags.isEmpty {
                Section {
                    // pinned tag filter bar — no rows
                } header: {
                    VStack(spacing: 0) {
                        tagFilterBar(loadedState)
                        Divider()
                    }
                    .listRowInsets(EdgeInsets())
                }
            }
            ForEach(loadedState.groupedConversations) { section in
                Section {
                    ForEach(section.conversations) { conversation in
                        conversationRow(conversation, loadedState: loadedState)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 2, bottom: 4, trailing: 2))
                            .contextMenu {
                                conversationContextMenu(conversation)
                            }
                            .popoverTip(organizationTip(for: conversation, loadedState: loadedState))
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    conversationToDelete = conversation
                                } label: {
                                    Label(String(localized: "Delete"), systemImage: "trash")
                                }
                                .tint(.red)
                            }
                    }
                } header: {
                    sectionHeader(for: section)
                }
            }
        }
        .listStyle(.plain)
#if os(iOS)
        .frame(maxWidth: 900)
#endif
        .frame(maxWidth: .infinity)
#if os(iOS)
        .refreshable {
            await viewModel.refreshAsync()
        }
#endif
    }

    @ViewBuilder
    func conversationContextMenu(_ conversation: Conversation) -> some View {
        Button {
            AppTips.conversationOrganization.invalidate(reason: .actionPerformed)
            viewModel.send(.pinToggled(conversation.id))
        } label: {
            Label(
                conversation.isPinned ? String(localized: "Unpin") : String(localized: "Pin"),
                systemImage: conversation.isPinned ? "pin.slash" : "pin"
            )
        }

        Button {
            AppTips.conversationOrganization.invalidate(reason: .actionPerformed)
            renameText = conversationTitle(conversation)
            renamingConversation = conversation
        } label: {
            Label(String(localized: "Rename"), systemImage: "pencil")
        }

        Button {
            AppTips.conversationOrganization.invalidate(reason: .actionPerformed)
            editingTagsConversation = conversation
        } label: {
            Label(String(localized: "Edit Tags"), systemImage: "tag")
        }

        if let url = exportURL(for: conversation) {
            ShareLink(item: url) {
                Label(String(localized: "Export"), systemImage: "square.and.arrow.up")
            }
        }

        Divider()

        Button(role: .destructive) {
            AppTips.conversationOrganization.invalidate(reason: .actionPerformed)
            conversationToDelete = conversation
        } label: {
            Label(String(localized: "Delete"), systemImage: "trash")
        }
    }

    @ViewBuilder
    func sectionHeader(for section: ConversationSection) -> some View {
        HStack(spacing: 4) {
            if section.period == .pinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
            }
            Text(section.period.localizedTitle)
                .font(.poppins(.semiBold, size: 11, relativeTo: .caption2))
        }
        .foregroundStyle(.secondary)
        .textCase(nil)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets())
        .background(.bar)
    }

    func tagFilterBar(_ loadedState: ConversationListViewModel.LoadedState) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                tagChip(
                    label: String(localized: "All"),
                    systemImage: "tag",
                    iconColor: Color.primary.opacity(0.7),
                    isSelected: loadedState.activeTagFilter == nil
                ) {
                    viewModel.send(.tagFilterChanged(nil))
                }
                ForEach(loadedState.allTags, id: \.name) { tag in
                    tagChip(
                        label: tag.name,
                        systemImage: "tag.fill",
                        iconColor: tag.color.displayColor,
                        isSelected: loadedState.activeTagFilter == tag.name
                    ) {
                        viewModel.send(.tagFilterChanged(loadedState.activeTagFilter == tag.name ? nil : tag.name))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    func tagChip(label: String, systemImage: String, iconColor: Color, isSelected: Bool,
                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .foregroundStyle(isSelected ? .white : iconColor)
                Text(label)
                    .foregroundStyle(isSelected ? .white : .primary)
            }
            .font(.caption)
            .fontWeight(.medium)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
#if os(macOS)
            .background(isSelected ? Color.appAccent : Color.primary.opacity(0.08), in: .capsule)
#else
            .glassEffect(
                isSelected ? .regular.tint(Color.appAccent).interactive() : .regular.interactive(),
                in: .capsule
            )
#endif
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
#if os(iOS)
        .frame(minHeight: 44)
#endif
    }
}

#Preview {
    NavigationStack {
        ConversationListView { _ in } onPrivateChatSelected: {}
            .navigationTitle(String(localized: "Chats"))
    }
}
