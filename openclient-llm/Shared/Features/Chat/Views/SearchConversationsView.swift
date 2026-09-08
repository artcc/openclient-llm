//
//  SearchConversationsView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 03/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct SearchConversationsView: View {
    // MARK: - Properties

    @Environment(\.scenePhase) private var scenePhase

    @State private var viewModel = ConversationListViewModel()
    @State private var searchText = ""
    @State private var selectedConversation: Conversation?

    // MARK: - View

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .loading:
                    ProgressView()
                        .accessibilityLabel(String(localized: "Loading conversations..."))
                        .tint(.secondary)
                case .loaded(let loadedState):
                    searchContent(loadedState)
                }
            }
            .navigationTitle(String(localized: "Search"))
            .navigationDestination(item: $selectedConversation) { conversation in
                ChatView(conversation: conversation) {
                    viewModel.refresh()
                }
            }
        }
        #if os(iOS)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: String(localized: "Search conversations...")
        )
        #else
        .searchable(
            text: $searchText,
            prompt: String(localized: "Search conversations...")
        )
        #endif
        .onChange(of: searchText) { _, newValue in
            viewModel.send(.searchChanged(newValue))
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                viewModel.refresh()
            }
        }
        .task {
            viewModel.send(.viewAppeared)
        }
    }
}

// MARK: - Private

private extension SearchConversationsView {
    @ViewBuilder
    func searchContent(_ loadedState: ConversationListViewModel.LoadedState) -> some View {
        if !searchText.isEmpty && loadedState.filteredConversations.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            let conversations = searchText.isEmpty
                ? loadedState.conversations
                : loadedState.filteredConversations

            if conversations.isEmpty {
                emptyState
            } else {
                resultsList(conversations)
            }
        }
    }

    var emptyState: some View {
        ContentUnavailableView {
            Label(
                String(localized: "No Conversations"),
                systemImage: "bubble.left.and.bubble.right"
            )
        } description: {
            Text(String(localized: "Start a new conversation to begin chatting"))
        }
    }

    func resultsList(_ conversations: [Conversation]) -> some View {
        List {
            ForEach(conversations) { conversation in
                Button {
                    selectedConversation = conversation
                } label: {
                    conversationRow(conversation)
                }
                .accessibilityValue(conversation.isPinned ? String(localized: "Pinned") : "")
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 2, bottom: 4, trailing: 2))
            }
        }
        .listStyle(.plain)
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity)
    }

    func conversationRow(_ conversation: Conversation) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: conversation.isPinned ? "pin.fill" : "sparkles")
                .accessibilityHidden(true)
                .font(.system(size: 14))
                .foregroundStyle(conversation.isPinned ? .orange : Color.appAccent)
#if os(macOS)
                .frame(width: 28, height: 28)
#else
                .frame(width: 32, height: 32)
#endif
                .glassEffect(.regular, in: .circle)

            VStack(alignment: .leading, spacing: 4) {
                Text(conversationTitle(conversation))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let lastMessage = conversation.messages.last(where: { $0.role != .system }) {
                    Text(lastMessage.content)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(formattedDate(conversation.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                    .padding(.vertical, 2)
            }
            .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 12)
#if os(macOS)
        .padding(.vertical, 6)
#else
        .padding(.vertical, 8)
#endif
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .buttonStyle(.plain)
    }

    func conversationTitle(_ conversation: Conversation) -> String {
        if !conversation.title.isEmpty {
            return conversation.title
        }
        if let firstUserMessage = conversation.messages.first(where: { $0.role == .user }) {
            let preview = firstUserMessage.content.prefix(50)
            return preview.count < firstUserMessage.content.count
                ? "\(preview)..."
                : String(preview)
        }
        return String(localized: "New Chat")
    }

    func formattedDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        } else if calendar.isDateInYesterday(date) {
            return String(localized: "Yesterday")
        } else if let daysAgo = calendar.dateComponents([.day], from: date, to: .now).day, daysAgo < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        } else {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
    }
}

#Preview {
    SearchConversationsView()
}

#Preview("Search result with large text") {
    SearchConversationsView()
        .conversationRow(Conversation(
            title: "Review the interface across iPhone, iPad, and Mac",
            modelId: "Preview",
            messages: [.init(role: .assistant, content: "Compare the layouts at different window sizes.")]
        ))
        .frame(width: 320)
        .padding()
        .environment(\.dynamicTypeSize, .accessibility1)
}
