//
//  ToolsView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 11/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct ToolsView: View {
    // MARK: - Properties

    @State private var viewModel = ToolsViewModel()
    @Environment(\.dismiss) private var dismiss

    // MARK: - View

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .loading:
                    ProgressView()
                        .accessibilityLabel(String(localized: "Loading tools..."))
                        .tint(.secondary)
                case .loaded(let loadedState):
                    toolsList(loadedState)
                }
            }
            .navigationTitle(String(localized: "Tools"))
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
        .task { viewModel.send(.viewAppeared) }
        .onReceive(NotificationCenter.default.publisher(for: .builtInToolSettingsDidChange)) { _ in
            viewModel.send(.viewAppeared)
        }
    }
}

// MARK: - Private

private extension ToolsView {
    var sortedTools: [BuiltInTool] {
        BuiltInTool.allCases.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    func toolsList(_ state: ToolsViewModel.LoadedState) -> some View {
        List {
            Section {
                ForEach(sortedTools) { tool in
                    toolRow(tool, isEnabled: state.enabledTools.contains(tool))
                }
            } header: {
                Text(String(localized: "Built-in Tools"))
            } footer: {
                Text(String(localized: """
                    Choose which OpenClient tools the assistant can use. \
                    Tools require a model that supports tool calling. \
                    Image tools may make additional model requests.
                    """))
            }
        }
    }

    func toolRow(_ tool: BuiltInTool, isEnabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7.5) {
            Text(tool.displayName)
                .font(.headline)
                .foregroundStyle(isEnabled ? .primary : .secondary)
            Text(tool.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text(verbatim: tool.rawValue)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Spacer()
                Toggle(String(localized: "Use \(tool.displayName)"), isOn: Binding(
                    get: { isEnabled },
                    set: { viewModel.send(.toolToggled(tool, enabled: $0)) }
                ))
                .labelsHidden()
            }
        }
        .padding(.horizontal, 4)
#if os(macOS)
        .padding(.vertical, 8)
#else
        .padding(.vertical, 6)
#endif
    }
}

#Preview {
    ToolsView()
}
