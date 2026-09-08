//
//  ChatInputBarView+MCP.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 14/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI
import TipKit

extension ChatInputBarView {
    var mcpButton: some View {
        let modelSupportsTools = state.selectedModel?.capabilities.contains(.functionCalling) == true
        return Button {
            AppTips.mcpServers.invalidate(reason: .actionPerformed)
            onMCPButtonTapped()
        } label: {
            Image(systemName: "server.rack")
                .font(.title2)
                .foregroundStyle(mcpColor(
                    supported: hasAvailableMCPTool && modelSupportsTools,
                    hasEnabled: hasEnabledMCPTool
                ))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .popoverTip(canShowMCPTip ? AppTips.mcpServers : nil, arrowEdge: .bottom)
        .accessibilityLabel(
            hasAvailableMCPTool && modelSupportsTools
                ? String(localized: "MCP Servers")
                : String(localized: "MCP Servers Unavailable")
        )
        .accessibilityValue(hasAvailableMCPTool && modelSupportsTools
            ? (hasEnabledMCPTool ? String(localized: "Tools enabled") : String(localized: "No tools enabled"))
            : "")
        .animation(.easeInOut(duration: 0.2), value: state.enabledMCPToolIds)
    }
}

extension ChatInputBarView {
    var availableMCPToolIds: Set<String> {
        state.availableMCPToolIds
    }

    var hasAvailableMCPTool: Bool { !availableMCPToolIds.isEmpty }

    var hasEnabledMCPTool: Bool {
        !state.enabledMCPToolIds.isDisjoint(with: availableMCPToolIds)
    }

    var canShowMCPTip: Bool {
        !state.isStreaming
            && !state.isRecording
            && !state.isTranscribing
            && !state.isSearchingWeb
            && hasAvailableMCPTool
            && state.selectedModel?.capabilities.contains(.functionCalling) == true
    }

    func mcpColor(supported: Bool, hasEnabled: Bool) -> Color {
        guard supported else { return .red }
        return hasEnabled ? Color.appAccent : .secondary
    }
}
