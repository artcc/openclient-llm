//
//  ConversationsOverviewWidget.swift
//  Widgets
//
//  Created by Arturo Carretero Calvo on 23/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI
import WidgetKit

// MARK: - ConversationsOverviewWidget

/// Large WidgetKit widget that shows up to 6 recent conversations (systemLarge) or 2 (systemMedium).
/// Each row links directly to the conversation via `openclient://conversation?id=`.
/// The header includes a "New Chat" link button.
/// Data is read from the shared App Group container written by the main app.
struct ConversationsOverviewWidget: Widget {
    // MARK: - Properties

    static let kind = AppGroupStore.conversationsWidgetKind

    // MARK: - Body

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ConversationsOverviewProvider()) { entry in
            ConversationsOverviewWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(String(localized: "Recent Conversations"))
        .description(String(localized: "See your latest conversations and jump back in."))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - ConversationsOverviewEntry

struct ConversationsOverviewEntry: TimelineEntry {
    let date: Date
    let conversations: [WidgetConversation]
}

// MARK: - ConversationsOverviewProvider

struct ConversationsOverviewProvider: TimelineProvider {
    func placeholder(in context: Context) -> ConversationsOverviewEntry {
        ConversationsOverviewEntry(date: Date(), conversations: placeholderConversations)
    }

    func getSnapshot(in context: Context, completion: @escaping (ConversationsOverviewEntry) -> Void) {
        let conversations = AppGroupStore.loadConversations()
        let entry = ConversationsOverviewEntry(
            date: Date(),
            conversations: conversations.isEmpty ? placeholderConversations : conversations
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ConversationsOverviewEntry>) -> Void) {
        let conversations = AppGroupStore.loadConversations()
        let entry = ConversationsOverviewEntry(date: Date(), conversations: conversations)
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()

        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

// MARK: - ConversationsOverviewWidgetView

private struct ConversationsOverviewWidgetView: View {
    // MARK: - Properties

    let entry: ConversationsOverviewEntry

    @Environment(\.widgetFamily) private var family

    // MARK: - View

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
                .padding(.vertical, 5)
            if entry.conversations.isEmpty {
                emptyState
            } else {
                conversationsList
            }
        }
    }
}

// MARK: - Private

private extension ConversationsOverviewWidgetView {
    var header: some View {
        HStack(alignment: .center) {
            Text(String(localized: "Recent"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Spacer()
            HStack(spacing: 5) {
                if let newChatURL = URL(string: "openclient://new-chat") {
                    Link(destination: newChatURL) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.15))
                                .frame(width: 25, height: 25)
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .accessibilityLabel(String(localized: "New Chat"))
                }
                if let searchURL = URL(string: "openclient://search") {
                    Link(destination: searchURL) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.15))
                                .frame(width: 25, height: 25)
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .accessibilityLabel(String(localized: "Search conversations"))
                }
            }
        }
        .padding(.horizontal, 2.5)
    }

    var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(String(localized: "No conversations yet"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var conversationsList: some View {
        let maxItems = family == .systemMedium ? 2 : 5
        return VStack(spacing: 0) {
            ForEach(Array(entry.conversations.prefix(maxItems).enumerated()), id: \.element.id) { index, conversation in
                if index > 0 {
                    Divider()
                        .padding(.leading, 12)
                }
                WidgetConversationRow(conversation: conversation)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Placeholder data

private let placeholderConversations: [WidgetConversation] = [
    WidgetConversation(
        id: UUID(),
        title: String(localized: "How does Swift concurrency work?"),
        modelId: "gpt-4o",
        lastMessagePreview: String(localized: "Swift uses structured concurrency with async/await..."),
        updatedAt: Date()
    ),
    WidgetConversation(
        id: UUID(),
        title: String(localized: "Recipe for pasta carbonara"),
        modelId: "claude-3-5-sonnet",
        lastMessagePreview: String(localized: "You'll need eggs, guanciale, Pecorino Romano..."),
        updatedAt: Date().addingTimeInterval(-3600)
    ),
    WidgetConversation(
        id: UUID(),
        title: String(localized: "Explain quantum entanglement"),
        modelId: "gpt-4o",
        lastMessagePreview: String(localized: "Quantum entanglement is a phenomenon where..."),
        updatedAt: Date().addingTimeInterval(-7200)
    )
]
