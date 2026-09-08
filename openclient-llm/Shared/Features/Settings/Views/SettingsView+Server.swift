//
//  SettingsView+Server.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 08/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

// MARK: - Server

extension SettingsView {
    func serverSection(_ loadedState: SettingsViewModel.LoadedState) -> some View {
        Section {
            serverURLField()
            apiKeyField()
            connectionStatusView(loadedState.connectionStatus)
            if let error = loadedState.serverPersistenceError {
                SettingsPersistenceErrorView(message: error, attempt: loadedState.serverPersistenceFailureCount)
            }
            testConnectionButton(loadedState)
            saveServerButton(loadedState)
        } header: {
            Text(String(localized: "Server"))
        } footer: {
            if loadedState.showLiteLLMHint {
                Label(liteLLMHintText, systemImage: "info.circle").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Private

private extension SettingsView {
    func serverURLField() -> some View {
        LabeledContent("Server URL") {
            TextField(String(localized: "Server URL"), text: $serverURL)
                .labelsHidden()
                .accessibilityLabel(String(localized: "Server URL"))
                .focused($focusedField, equals: .serverURL)
                .textSelection(.enabled)
                .textContentType(.URL)
                .autocorrectionDisabled()
#if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
#endif
                .onChange(of: serverURL) { _, newValue in
                    viewModel.send(.serverURLChanged(newValue))
                }
        }
    }

    func apiKeyField() -> some View {
        LabeledContent("API Key (Optional)") {
            HStack {
                Group {
                    if isAPIKeyVisible {
                        TextField(String(localized: "API Key (Optional)"), text: $apiKey)
                            .focused($focusedField, equals: .apiKey)
                    } else {
                        SecureField(String(localized: "API Key (Optional)"), text: $apiKey)
                            .focused($focusedField, equals: .apiKey)
                    }
                }
                .labelsHidden()
                .accessibilityLabel(String(localized: "API Key (Optional)"))
                .textSelection(.enabled)

                Button {
                    isAPIKeyVisible.toggle()
                } label: {
                    Image(systemName: isAPIKeyVisible ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
#if os(macOS)
                .buttonStyle(.borderless)
                .controlSize(.small)
#else
                .buttonStyle(.plain)
#endif
                .accessibilityLabel(
                    isAPIKeyVisible
                    ? String(localized: "Hide API Key")
                    : String(localized: "Show API Key")
                )
            }
        }
        .onChange(of: apiKey) { _, newValue in
            viewModel.send(.apiKeyChanged(newValue))
        }
    }

    func testConnectionButton(_ loadedState: SettingsViewModel.LoadedState) -> some View {
        Button {
            focusedField = nil
            viewModel.send(.testConnectionTapped)
        } label: {
            HStack(spacing: 8) {
                if loadedState.connectionStatus == .testing {
                    ProgressView()
                        .tint(.secondary)
                        .controlSize(.small)
                }
                Text(
                    loadedState.connectionStatus == .testing
                    ? String(localized: "Testing...")
                    : String(localized: "Test Connection")
                )
            }
        }
        .disabled(loadedState.serverURL.isEmpty || loadedState.connectionStatus == .testing)
#if os(macOS)
        .buttonStyle(.bordered)
#else
        .buttonStyle(.automatic)
        .tint(.primary)
#endif
    }

    func saveServerButton(_ loadedState: SettingsViewModel.LoadedState) -> some View {
        Button {
            focusedField = nil
            viewModel.send(.saveTapped)
        } label: {
            HStack {
                Text(String(localized: "Save"))
#if os(iOS)
                Spacer()
#endif
                if loadedState.isSaved {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityValue(loadedState.isSaved ? String(localized: "Saved") : "")
#if os(macOS)
        .buttonStyle(.borderedProminent)
#else
        .buttonStyle(.automatic)
        .tint(.primary)
#endif
    }

    @ViewBuilder
    func connectionStatusView(_ status: SettingsViewModel.ConnectionStatus) -> some View {
        switch status {
        case .idle, .testing:
            EmptyView()
        case .success:
            Label(String(localized: "Connection successful"), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}
