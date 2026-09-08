//
//  MCPToolsSheet.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 25/07/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct MCPToolsSheet: View {
    @Bindable var viewModel: ChatViewModel
    @Binding var isPresented: Bool

    var body: some View {
        Group {
            if case .loaded(let loadedState) = viewModel.state {
                loadedContent(loadedState)
            }
        }
    }
}

private extension MCPToolsSheet {
    func loadedContent(_ loadedState: ChatViewModel.LoadedState) -> some View {
        NavigationStack {
            Group {
                if loadedState.isLoadingMCPTools {
                    loadingContent
                } else if let error = loadedState.mcpToolsError,
                          loadedState.availableMCPServers.isEmpty {
                    errorContent(error)
                } else if loadedState.availableMCPServers.isEmpty {
                    emptyContent
                } else {
                    serverListView(loadedState)
                }
            }
            .navigationTitle(String(localized: "MCP Servers"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { doneToolbar }
            .toolbar { refreshToolbar(loadedState: loadedState) }
        }
    }

    var loadingContent: some View {
        VStack {
            Spacer()
            ProgressView()
                .tint(.secondary)
            Text(String(localized: "Loading tools..."))
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            Spacer()
        }
    }

    var emptyContent: some View {
        VStack {
            Spacer()
            Label(
                String(localized: "No MCP servers configured. Add them in your LiteLLM server's config.yaml."),
                systemImage: "server.rack"
            )
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            Spacer()
        }
    }

    func serverListView(_ loadedState: ChatViewModel.LoadedState) -> some View {
        List {
            if let error = loadedState.mcpToolsError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
            Section(String(localized: "MCP Servers")) {
                ForEach(loadedState.availableMCPServers) { server in
                    let serverTools = loadedState.toolsForServer(server.serverId)
                    NavigationLink {
                        serverDetailView(
                            server: server,
                            tools: serverTools,
                            loadedState: loadedState
                        )
                    } label: {
                        serverRow(server: server, tools: serverTools, loadedState: loadedState)
                    }
                }
            }
        }
    }

    func errorContent(_ error: String) -> some View {
        ContentUnavailableView {
            Label(String(localized: "Unable to Load MCP Tools"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(error)
        } actions: {
            Button(String(localized: "Retry")) {
                viewModel.send(.mcpToolsRefreshed)
            }
        }
    }

    func serverRow(
        server: MCPServerInfo,
        tools: [MCPToolInfo],
        loadedState: ChatViewModel.LoadedState
    ) -> some View {
        let isServerAvailable = !loadedState.failedMCPServerIds.contains(server.serverId)
        let enabled = tools.filter {
            isServerAvailable && $0.isInputSchemaSupported && loadedState.enabledMCPToolIds.contains($0.id)
        }.count
        return HStack {
            Image(systemName: isServerAvailable ? "server.rack" : "exclamationmark.triangle")
                .foregroundStyle(isServerAvailable ? (enabled > 0 ? Color.appAccent : .secondary) : .red)
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
            if isServerAvailable {
                Text(String(localized: "\(enabled)/\(tools.count)"))
                    .accessibilityLabel(Text("\(enabled) of \(tools.count) tools enabled"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(String(localized: "Unavailable"))
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    func serverDetailView(
        server: MCPServerInfo,
        tools: [MCPToolInfo],
        loadedState: ChatViewModel.LoadedState
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
            onRetry: { viewModel.send(.mcpToolsRefreshed) }
        )
        .navigationTitle(server.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ToolbarContentBuilder
    var doneToolbar: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button(String(localized: "Done")) {
                isPresented = false
            }
        }
    }

    @ToolbarContentBuilder
    func refreshToolbar(loadedState: ChatViewModel.LoadedState?) -> some ToolbarContent {
        let isLoading = loadedState?.isLoadingMCPTools ?? false
        ToolbarItem(placement: .cancellationAction) {
            Button {
                viewModel.send(.mcpToolsRefreshed)
            } label: {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.secondary)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(isLoading)
            .accessibilityLabel(String(localized: "Refresh"))
        }
    }
}

// MARK: - Helpers

extension ChatViewModel.LoadedState {
    func toolsForServer(_ serverId: String) -> [MCPToolInfo] {
        availableMCPTools.filter { $0.serverId == serverId }
    }
}

#Preview {
    let servers = [
        MCPServerInfo(serverId: "gh", serverName: "github", description: "Manage repos, issues, PRs", allowedTools: nil)
    ]
    let tool1 = MCPToolInfo(name: "search_issues", description: "Search GitHub issues",
        serverId: "gh", serverName: "github", inputSchema: nil)
    let tool2 = MCPToolInfo(name: "create_pr", description: "Create a pull request",
        serverId: "gh", serverName: "github", inputSchema: nil)
    return MCPToolsSheet(
        viewModel: ChatViewModel(state: .loaded(ChatViewModel.LoadedState(
            isMCPSupported: true,
            availableMCPTools: [tool1, tool2],
            availableMCPServers: servers,
            enabledMCPToolIds: [tool1.id],
            mcpToolPermissions: [tool1.id: .ask]
        ))),
        isPresented: .constant(true)
    )
}
