//
//  SettingsView+WebSearch.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 25/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

// MARK: - Web Search

extension SettingsView {
    func webSearchSection(_ loadedState: SettingsViewModel.LoadedState) -> some View {
        Section {
            webSearchToolContent(loadedState)
            webSearchLoadButton(loadedState)

            if let error = loadedState.searchToolsError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Stepper(
                value: Binding(
                    get: { loadedState.webSearchMaxResults },
                    set: { viewModel.send(.webSearchMaxResultsChanged($0)) }
                ),
                in: 1...20
            ) {
                HStack {
                    Text(String(localized: "Results"))
                    Spacer()
                    Text("\(loadedState.webSearchMaxResults)")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(String(localized: "Web Search"))
        } footer: {
            if loadedState.availableSearchTools.isEmpty {
                Text(String(localized: "Fetch the list of search tools configured in your LiteLLM server."))
            } else {
                let count = loadedState.availableSearchTools.count
                Text(String(localized: "\(count) search tool(s) available on your server."))
            }
        }
    }

    @ViewBuilder
    func webSearchToolContent(_ loadedState: SettingsViewModel.LoadedState) -> some View {
        if loadedState.availableSearchTools.isEmpty {
            Label(
                String(
                    localized: "No search tools loaded. Tap \"Load Available Tools\" to fetch them from your server."
                ),
                systemImage: "magnifyingglass"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        } else {
            Picker(
                String(localized: "Search Tool"),
                selection: Binding(
                    get: { loadedState.webSearchToolName },
                    set: { viewModel.send(.webSearchToolNameChanged($0)) }
                )
            ) {
                ForEach(loadedState.availableSearchTools) { tool in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tool.searchToolName)
                        Text(tool.searchProvider)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(tool.searchToolName)
                }
            }
        }
    }

    @ViewBuilder
    func webSearchLoadButton(_ loadedState: SettingsViewModel.LoadedState) -> some View {
        Button {
            viewModel.send(.fetchSearchToolsTapped)
        } label: {
            HStack {
                if loadedState.isLoadingSearchTools {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.secondary)
                    Text(String(localized: "Loading..."))
                        .foregroundStyle(.secondary)
                } else {
                    Label(
                        loadedState.availableSearchTools.isEmpty
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
        .disabled(loadedState.isLoadingSearchTools)
    }
}
