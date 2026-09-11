//
//  Notification.Name.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 03/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

extension Notification.Name {
    /// Posted after the user confirms a full app data reset.
    /// ChatViewModel and ModelsViewModel observe this to reload their state.
    static let appDataDidReset = Notification.Name("openclient.appDataDidReset")
    /// Posted whenever a conversation is persisted (message sent, updated, etc.).
    /// ConversationListViewModel observes this to reload the list without recreating views.
    nonisolated static let conversationDidUpdate = Notification.Name("openclient.conversationDidUpdate")
    nonisolated static let promptTemplatesDidChangeExternally = Notification.Name(
        "openclient.promptTemplatesDidChangeExternally"
    )
    nonisolated static let cloudSyncIntentDidChange = Notification.Name("openclient.cloudSyncIntentDidChange")
    nonisolated static let serverConfigurationDidChange = Notification.Name(
        "openclient.serverConfigurationDidChange"
    )
    nonisolated static let mcpToolSettingsDidChange = Notification.Name(
        "openclient.mcpToolSettingsDidChange"
    )
    nonisolated static let builtInToolSettingsDidChange = Notification.Name(
        "openclient.builtInToolSettingsDidChange"
    )
}
