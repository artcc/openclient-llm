//
//  AppTips.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 14/07/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation
import SwiftUI
import TipKit

enum AppTips {
    // MARK: - Tips

    static let modelSelector = ModelSelectorTip()
    static let modelCapabilities = ModelCapabilitiesTip()
    static let chatAttachments = ChatAttachmentsTip()
    static let messageActions = MessageActionsTip()
    static let webSearch = WebSearchTip()
    static let chatOptions = ChatOptionsTip()
    static let privateChat = PrivateChatTip()
    static let contextUsage = ContextUsageTip()
    static let memory = MemoryTip()
    static let conversationOrganization = ConversationOrganizationTip()
    static let mcpServers = MCPServersTip()
    static let appIconSelection = AppIconSelectionTip()

    static let allTips: [any Tip] = [
        modelSelector,
        modelCapabilities,
        chatAttachments,
        messageActions,
        webSearch,
        chatOptions,
        privateChat,
        contextUsage,
        memory,
        conversationOrganization,
        mcpServers,
        appIconSelection
    ]

    // MARK: - Configuration

    static func configure() {
        do {
            try Tips.configure([
                .displayFrequency(.hourly)
            ])
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-showAllFeatureTips") {
                Tips.showAllTipsForTesting()
            }
#endif
        } catch {
            LogManager.error("Unable to configure TipKit: \(error.localizedDescription)")
        }
    }

    static func resetEligibility() async {
        for tip in allTips {
            await tip.resetEligibility()
        }
    }
}
