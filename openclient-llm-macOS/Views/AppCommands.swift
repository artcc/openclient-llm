//
//  AppCommands.swift
//  openclient-llm-macOS
//
//  Created by Arturo Carretero Calvo on 31/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct AppCommands: Commands {
    // MARK: - Properties

    @FocusedValue(\.conversationListViewModel) private var conversationListViewModel

    // MARK: - View

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(String(localized: "New Chat")) {
                conversationListViewModel?.send(.newConversationTapped)
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(conversationListViewModel == nil)

            Button(String(localized: "New Private Chat")) {
                conversationListViewModel?.send(.newPrivateConversationTapped)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(conversationListViewModel == nil)

            Divider()
        }
    }
}

// MARK: - FocusedValues

extension FocusedValues {
    @Entry var conversationListViewModel: ConversationListViewModel?
}
