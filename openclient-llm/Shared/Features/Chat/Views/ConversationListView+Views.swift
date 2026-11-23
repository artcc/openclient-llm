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
        let isSelecting = viewModel.moveSelection != nil
        let isSelected = viewModel.moveSelection?.contains(conversation.id) ?? (activeConversationId == conversation.id)
        let rowSymbol = isSelecting ? (isSelected ? "checkmark.circle.fill" : "circle")
            : (conversation.isPinned ? "pin.fill" : "sparkles")

        return Button { viewModel.activateRow(conversation) } label: {
            HStack(alignment: .top, spacing: 10) {
                rowIcon(rowSymbol, isPinned: conversation.isPinned, isSelected: isSelected)
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
                    conversationMetadata(conversation, loaded: loadedState)
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
        .accessibilityHint(isSelecting ? String(localized: "Select or deselect this chat to move it.") : "")
        .disabled(isSelecting && viewModel.isSavingFolderChange)
#if os(macOS)
        .draggable(ChatFolderDrag(ids: dragIDs(for: conversation.id)))
#endif
    }

#if os(macOS)
    private func dragIDs(for id: UUID) -> [UUID] {
        guard let selection = viewModel.moveSelection, selection.contains(id) else { return [id] }
        return Array(selection)
    }
#endif

    private func rowIcon(_ symbol: String, isPinned: Bool, isSelected: Bool) -> some View {
        Image(systemName: symbol)
            .accessibilityHidden(true)
            .font(.system(size: 14))
            .foregroundStyle(isSelected ? .white : (isPinned ? .orange : Color.appAccent))
#if os(macOS)
            .frame(width: 28, height: 28)
#else
            .frame(width: 32, height: 32)
#endif
            .glassEffect(isSelected ? .regular.tint(Color.appAccent) : .regular, in: .circle)
    }

    func conversationMetadata(_ conversation: Conversation,
                              loaded: ConversationListViewModel.LoadedState) -> some View {
        FlowLayout(spacing: 4) {
            Text(formattedDate(conversation.updatedAt))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 180, alignment: .leading)
                .padding(.vertical, 2)
            if showsFolderName(in: loaded),
               let folder = loaded.folderName(for: conversation.id) {
                ConversationFolderCaption(name: folder)
            }
            branchBadge(for: conversation)
            modelBadge(conversation.modelId)
            ForEach(conversation.tags.prefix(3), id: \.self) { tag in
                tagBadge(tag)
            }
        }
        .padding(.top, 2)
    }

    private func showsFolderName(in loaded: ConversationListViewModel.LoadedState) -> Bool {
        loaded.hasLoadedFolders && (loaded.folderScope == .all || loaded.searchesAllFolders)
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

struct ConversationFolderCaption: View {
    let name: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "folder")
                .accessibilityHidden(true)
            Text(verbatim: name)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(maxWidth: 180, alignment: .leading)
        .padding(.vertical, 2)
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
    let folder = ConversationFolder(id: UUID(), name: "Client projects", updatedAt: .now)
    let loaded = ConversationListViewModel.LoadedState(
        folders: [folder], folderIDs: [conversation.id: folder.id], hasLoadedFolders: true
    )
    ConversationListView(viewModel: ConversationListViewModel(), folderScope: .constant(.all),
                         onConversationSelected: { _ in }, onPrivateChatSelected: {})
        .conversationRow(conversation, loadedState: loaded)
        .frame(width: 320)
        .padding()
}
