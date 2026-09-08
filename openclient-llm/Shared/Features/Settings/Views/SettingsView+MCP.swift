//
//  SettingsView+MCP.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 25/07/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

extension SettingsView {
    func mcpSection(_ loadedState: SettingsViewModel.LoadedState) -> some View {
        Section {
            if loadedState.isLoadingMCPTools {
                loadingRow
            } else {
                mcpStatusRow(loadedState)
                mcpRefreshButton(loadedState)
                mcpServerRows(loadedState)
                if let error = loadedState.mcpToolsError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text(String(localized: "MCP Servers"))
        } footer: {
            mcpSectionFooter(loadedState)
        }
    }

    var loadingRow: some View {
        HStack {
            ProgressView()
                .controlSize(.small)
                .tint(.secondary)
            Text(String(localized: "Loading..."))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    func mcpServerRows(_ loadedState: SettingsViewModel.LoadedState) -> some View {
        if !loadedState.availableMCPServers.isEmpty {
            ForEach(loadedState.availableMCPServers) { server in
                let serverTools = loadedState.toolsForServer(server.serverId)
                let isServerAvailable = !loadedState.failedMCPServerIds.contains(server.serverId)
                let enabled = serverTools.filter {
                    isServerAvailable && $0.isInputSchemaSupported
                        && loadedState.enabledMCPToolIds.contains($0.id)
                }.count
                Button {
                    mcpServerSheet = server
                } label: {
                    serverRowLabel(
                        server: server,
                        enabled: enabled,
                        total: serverTools.count,
                        isAvailable: isServerAvailable
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    func mcpSectionFooter(_ loadedState: SettingsViewModel.LoadedState) -> some View {
        if loadedState.isLoadingMCPTools {
            EmptyView()
        } else if loadedState.availableMCPServers.isEmpty {
            Text(String(localized: """
                MCP servers are configured in your LiteLLM server. \
                Fetch to see what's available, enable tools, and choose their execution permissions.
                """))
        } else {
            let availableTools = loadedState.availableMCPTools.filter {
                $0.isInputSchemaSupported && !loadedState.failedMCPServerIds.contains($0.serverId)
            }
            let enabled = availableTools.filter { loadedState.enabledMCPToolIds.contains($0.id) }.count
            let total = availableTools.count
            Text(enabledMCPToolSummary(enabled: enabled, total: total))
        }
    }

    func mcpToolSheet(
        server: MCPServerInfo,
        loadedState: SettingsViewModel.LoadedState
    ) -> some View {
        NavigationStack {
            let tools = loadedState.toolsForServer(server.serverId)
            serverToolListView(server: server, tools: tools, loadedState: loadedState)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            mcpServerSheet = nil
                            viewModel.send(.fetchMCPToolsTapped)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel(String(localized: "Refresh"))
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Done")) { mcpServerSheet = nil }
                    }
                }
        }
    }

    func serverRowLabel(server: MCPServerInfo, enabled: Int, total: Int, isAvailable: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(server.displayName)
                    .font(.headline)
                if let description = server.displayDescription {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isAvailable {
                Text("\(enabled)/\(total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label(String(localized: "Unavailable"), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
#if os(macOS)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
#endif
        }
#if os(macOS)
        .contentShape(.rect)
#endif
    }

    @ViewBuilder
    func mcpStatusRow(_ loadedState: SettingsViewModel.LoadedState) -> some View {
        if loadedState.availableMCPServers.isEmpty, loadedState.mcpToolsError == nil {
            // swiftlint:disable line_length
            Label(
                String(localized: "No MCP servers loaded. Tap \"Load Available Tools\" to fetch them from your server."),
                systemImage: "server.rack"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            // swiftlint:enable line_length
        } else if !loadedState.availableMCPServers.isEmpty {
            let count = loadedState.availableMCPServers.filter {
                !loadedState.failedMCPServerIds.contains($0.serverId)
            }.count
            if count > 0 {
                Label(availableMCPServerCountText(count), systemImage: "server.rack")
            } else {
                Label(String(localized: "MCP servers unavailable"), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    func mcpRefreshButton(_ loadedState: SettingsViewModel.LoadedState) -> some View {
        Button {
            viewModel.send(.fetchMCPToolsTapped)
        } label: {
            HStack {
                if loadedState.isLoadingMCPTools {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.secondary)
                    Text(String(localized: "Loading..."))
                        .foregroundStyle(.secondary)
                } else {
                    Label(
                        loadedState.availableMCPServers.isEmpty
                            ? String(localized: "Load Available Tools")
                            : String(localized: "Refresh Tools"),
                        systemImage: "arrow.clockwise"
                    )
                }
            }
        }
        #if os(macOS)
        .buttonStyle(.bordered)
        #else
        .buttonStyle(.plain)
        #endif
        .disabled(loadedState.isLoadingMCPTools)
    }

    @ViewBuilder
    func serverToolListView(
        server: MCPServerInfo,
        tools: [MCPToolInfo],
        loadedState: SettingsViewModel.LoadedState
    ) -> some View {
        MCPServerToolsView(
            tools: tools,
            isServerAvailable: !loadedState.failedMCPServerIds.contains(server.serverId),
            enabledToolIds: loadedState.enabledMCPToolIds,
            permissions: loadedState.mcpToolPermissions,
            onToolEnabledChanged: { toolId, enabled in
                viewModel.send(.mcpToolToggled(toolId: toolId, enabled: enabled))
            },
            onAllToolsEnabledChanged: { enabled in
                viewModel.send(.mcpToolsToggled(toolIds: tools.map(\.id), enabled: enabled))
            },
            onPermissionChanged: { toolId, permission in
                viewModel.send(.mcpToolPermissionChanged(toolId: toolId, permission: permission))
            },
            onAllPermissionsChanged: { permission in
                viewModel.send(.mcpToolsPermissionChanged(toolIds: tools.map(\.id), permission: permission))
            },
            onRetry: {
                mcpServerSheet = nil
                viewModel.send(.fetchMCPToolsTapped)
            }
        )
        .navigationTitle(server.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    func availableMCPServerCountText(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 server available")
            : String(localized: "\(count) servers available")
    }

    func enabledMCPToolSummary(enabled: Int, total: Int) -> String {
        if total == 1 {
            return String(localized: """
                \(enabled) of 1 MCP tool enabled. \
                Availability and permissions can also be managed from the chat input bar.
                """)
        }
        return String(localized: """
            \(enabled) of \(total) MCP tools enabled. \
            Availability and permissions can also be managed from the chat input bar.
            """)
    }

}

extension SettingsViewModel.LoadedState {
    func toolsForServer(_ serverId: String) -> [MCPToolInfo] {
        availableMCPTools.filter { $0.serverId == serverId }
    }
}
