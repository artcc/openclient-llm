//
//  MCPServerToolsView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 14/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct MCPServerToolsView: View {
    let tools: [MCPToolInfo]
    let isServerAvailable: Bool
    let enabledToolIds: Set<String>
    let permissions: [String: MCPToolPermission]
    let onToolEnabledChanged: @MainActor @Sendable (String, Bool) -> Void
    let onAllToolsEnabledChanged: @MainActor @Sendable (Bool) -> Void
    let onPermissionChanged: @MainActor @Sendable (String, MCPToolPermission) -> Void
    let onAllPermissionsChanged: @MainActor @Sendable (MCPToolPermission) -> Void
    let onRetry: @MainActor @Sendable () -> Void

    var body: some View {
        if tools.isEmpty {
            MCPServerToolsEmptyView(didFail: !isServerAvailable, onRetry: onRetry)
        } else {
            List {
                availabilitySection
                enableAllSection
                toolRowsSection
            }
        }
    }
}

private extension MCPServerToolsView {
    var configurableTools: [MCPToolInfo] { tools.filter(\.isInputSchemaSupported) }

    var allEnabled: Bool {
        !configurableTools.isEmpty && configurableTools.allSatisfy { enabledToolIds.contains($0.id) }
    }

    var commonPermission: MCPToolPermission? {
        let values = Set(configurableTools.map { permissions[$0.id] ?? .ask })
        return values.count == 1 ? values.first : nil
    }

    @ViewBuilder
    var availabilitySection: some View {
        if !isServerAvailable {
            Section {
                Label(
                    String(localized: "These tools are unavailable until this server refreshes successfully."),
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.red)
            }
        }
    }

    var enableAllSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { allEnabled },
                set: { enabled in onAllToolsEnabledChanged(enabled) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Enable All Tools"))
                        .font(.headline)
                    Text(isServerAvailable
                        ? availableToolCountText(configurableTools.count)
                        : String(localized: "Tools unavailable"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .disabled(!isServerAvailable || configurableTools.isEmpty)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Permission"))
                    Text(String(localized: "All"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Menu {
                    ForEach(MCPToolPermission.allCases, id: \.self) { option in
                        Button {
                            onAllPermissionsChanged(option)
                        } label: {
                            Label(
                                option.title,
                                systemImage: option == commonPermission ? "checkmark" : option.systemImage
                            )
                        }
                        .accessibilityAddTraits(option == commonPermission ? .isSelected : [])
                    }
                } label: {
                    Label(
                        commonPermission?.title ?? String(localized: "Custom"),
                        systemImage: commonPermission?.systemImage ?? "slider.horizontal.3"
                    )
                }
            }
            .disabled(!isServerAvailable || configurableTools.isEmpty)
        }
    }

    var toolRowsSection: some View {
        Section {
            ForEach(tools) { tool in
                MCPToolPermissionRow(
                    tool: tool,
                    isEnabled: enabledToolIds.contains(tool.id),
                    isAvailable: isServerAvailable && tool.isInputSchemaSupported,
                    permission: permissions[tool.id] ?? .ask,
                    onEnabledChanged: { onToolEnabledChanged(tool.id, $0) },
                    onPermissionChanged: { onPermissionChanged(tool.id, $0) }
                )
            }
        } footer: {
            Text(String(localized: """
                Permissions apply to this device and the current MCP server configuration.
                """))
                .lineLimit(nil)
                .padding(.top, 10)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    func availableToolCountText(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 tool available")
            : String(localized: "\(count) tools available")
    }
}

#Preview {
    let first = MCPToolInfo(
        name: "create_issue",
        description: "Create an issue in a repository",
        serverId: "github",
        serverName: "GitHub",
        inputSchema: nil
    )
    let second = MCPToolInfo(
        name: "search_repositories",
        description: "Search repositories",
        serverId: "github",
        serverName: "GitHub",
        inputSchema: nil
    )
    MCPServerToolsView(
        tools: [first, second],
        isServerAvailable: true,
        enabledToolIds: [],
        permissions: [first.id: .alwaysAllow, second.id: .ask],
        onToolEnabledChanged: { _, _ in },
        onAllToolsEnabledChanged: { _ in },
        onPermissionChanged: { _, _ in },
        onAllPermissionsChanged: { _ in },
        onRetry: {}
    )
}

#Preview("Unavailable") {
    MCPServerToolsView(
        tools: [MCPToolInfo(
            name: "create_issue",
            description: "Create an issue in a repository",
            serverId: "github",
            serverName: "GitHub",
            inputSchema: nil
        )],
        isServerAvailable: false,
        enabledToolIds: [],
        permissions: [:],
        onToolEnabledChanged: { _, _ in },
        onAllToolsEnabledChanged: { _ in },
        onPermissionChanged: { _, _ in },
        onAllPermissionsChanged: { _ in },
        onRetry: {}
    )
}
