//
//  ConversationListViewModel+Filter.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 10/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

extension ConversationListViewModel {
    enum FilterEvent {
        case searchChanged(String)
        case tagChanged(String?)
        case scopeChanged(ConversationFolderScope)
        case searchAllFolders(Bool)
    }

    func applySearchFilter(_ loadedState: inout LoadedState) {
        let query = loadedState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            loadedState.searchesAllFolders = false
        }
        let scoped = loadedState.scopedConversations
        if let tag = loadedState.activeTagFilter, !scoped.contains(where: { $0.tags.contains { $0.name == tag } }) {
            loadedState.activeTagFilter = nil
        }
        var base = loadedState.searchesAllFolders ? loadedState.conversations : scoped
        if let tag = loadedState.activeTagFilter, !loadedState.searchesAllFolders {
            base = base.filter { $0.tags.contains { $0.name == tag } }
        }
        if !query.isEmpty {
            base = base.filter { conversation in
                conversation.title.lowercased().contains(query)
                    || conversation.messages.contains { $0.content.lowercased().contains(query) }
            }
        }
        loadedState.filteredConversations = base
        if moveSelection != nil {
            moveSelection?.formIntersection(base.map(\.id))
        }
    }
}

extension ConversationListViewModel.LoadedState {
    var groupedConversations: [ConversationSection] { ConversationSection.group(filteredConversations) }
    var allTags: [ConversationTag] { tags(in: conversations) }
    var scopedTags: [ConversationTag] { tags(in: scopedConversations) }

    private func tags(in conversations: [Conversation]) -> [ConversationTag] {
        let tags = Dictionary(conversations.flatMap(\.tags).map { ($0.name, $0) },
                              uniquingKeysWith: { first, _ in first }).values
        return tags.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
