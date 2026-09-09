//
//  ConversationListView+Views.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 25/07/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

extension ConversationListView {
    func conversationRow(
        _ conversation: Conversation,
        loadedState: ConversationListViewModel.LoadedState
    ) -> some View {
        let isSelected = activeConversationId == conversation.id

        return Button {
            viewModel.send(.conversationTapped(conversation))
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: conversation.isPinned ? "pin.fill" : "sparkles")
                    .accessibilityHidden(true)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? .white : (conversation.isPinned ? .orange : Color.appAccent))
#if os(macOS)
                    .frame(width: 28, height: 28)
#else
                    .frame(width: 32, height: 32)
#endif
                    .glassEffect(isSelected ? .regular.tint(Color.appAccent) : .regular, in: .circle)
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
                    conversationMetadata(conversation)
                }
                .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 12)
#if os(macOS)
            .padding(.vertical, 6)
#else
            .padding(.vertical, 8)
#endif
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.appAccent.opacity(0.12))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(conversation.isPinned ? String(localized: "Pinned") : "")
    }

    func conversationMetadata(_ conversation: Conversation) -> some View {
        FlowLayout(spacing: 4) {
            Text(formattedDate(conversation.updatedAt))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 180, alignment: .leading)
                .padding(.vertical, 2)
            branchBadge(for: conversation)
            modelBadge(conversation.modelId)
            ForEach(conversation.tags.prefix(3), id: \.self) { tag in
                tagBadge(tag)
            }
        }
        .padding(.top, 2)
    }

    func modelBadge(_ modelId: String) -> some View {
        let name = modelId.split(separator: "/").last.map(String.init) ?? modelId
        return Text(name)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: 180, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.secondary.opacity(0.12), in: .capsule)
    }

    func tagBadge(_ tag: ConversationTag) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "tag.fill")
                .foregroundStyle(tag.color.displayColor)
            Text(tag.name)
                .foregroundStyle(.primary)
        }
        .font(.caption2)
        .fontWeight(.medium)
        .lineLimit(1)
        .frame(maxWidth: 180, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tag.color.displayColor.opacity(0.12), in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(tag.name), \(tag.color.localizedName)"))
    }

    @ViewBuilder
    func branchBadge(for conversation: Conversation) -> some View {
        if conversation.parentConversationId != nil {
            Image(systemName: "arrow.branch")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityLabel(String(localized: "Forked conversation"))
        }
    }
}

#Preview("Conversation with long metadata") {
    let conversation = Conversation(
        title: "Review the interface across iPhone, iPad, and Mac",
        modelId: "provider/a-model-with-a-long-descriptive-identifier",
        messages: [.init(role: .assistant, content: "Compare the layouts at different window sizes.")],
        isPinned: true,
        tags: [.init(name: "Interface review", color: .orange), .init(name: "Accessibility", color: .orange)],
        parentConversationId: UUID()
    )
    ConversationListView(onConversationSelected: { _ in }, onPrivateChatSelected: {})
        .conversationRow(conversation, loadedState: .init())
        .frame(width: 320)
        .padding()
}
