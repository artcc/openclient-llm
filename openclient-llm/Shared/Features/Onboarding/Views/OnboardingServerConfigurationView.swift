//
//  OnboardingServerConfigurationView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 07/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct OnboardingServerConfigurationView: View {
    // MARK: - Properties

    @Binding var serverURL: String
    @Binding var apiKey: String
    @Binding var isAPIKeyVisible: Bool

    let state: OnboardingViewModel.LoadedState
    let onEvent: (OnboardingViewModel.Event) -> Void

    @FocusState private var focusedField: Field?
    @AccessibilityFocusState private var isErrorFocused: Bool

    private enum Field: Hashable {
        case serverURL
        case apiKey
    }

    // MARK: - View

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Connect Your Server")
                    .font(.poppins(.semiBold, size: 28, relativeTo: .title))
                    .accessibilityAddTraits(.isHeader)
                Text("Add your server details, then test the connection before continuing.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 20) {
                serverURLField
                apiKeyField
            }

            connectionSection
        }
        .onChange(of: serverURL) { _, newValue in
            onEvent(.serverURLChanged(newValue))
        }
        .onChange(of: apiKey) { _, newValue in
            onEvent(.apiKeyChanged(newValue))
        }
        .onChange(of: state.connectionStatus) { _, newValue in
            if case .failure = newValue {
                isErrorFocused = true
            } else {
                isErrorFocused = false
            }
        }
    }
}

// MARK: - Private

private extension OnboardingServerConfigurationView {
    var serverURLField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Server URL")
                .font(.subheadline.weight(.medium))

            TextField(Constants.URLs.serverUrl, text: $serverURL)
                .font(.system(.body, design: .monospaced))
                .textContentType(.URL)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .serverURL)
                .accessibilityLabel("Server URL")
#if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .submitLabel(.next)
                .textFieldStyle(.plain)
                .padding(12)
                .frame(minHeight: 44)
                .background(.background.secondary, in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(focusedField == .serverURL ? Color.appAccent : Color.clear, lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
#else
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
#endif
                .onSubmit { focusedField = .apiKey }

            Text("Use the base URL of your OpenAI-compatible server.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var apiKeyField: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Text("API Key").fontWeight(.medium)
                    Text("Optional").foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("API Key").fontWeight(.medium)
                    Text("Optional").foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)

            HStack(spacing: 0) {
                Group {
                    if isAPIKeyVisible {
                        TextField("API Key", text: $apiKey)
                    } else {
                        SecureField("API Key", text: $apiKey)
                    }
                }
                .font(.body)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .apiKey)
                .accessibilityLabel("API Key, optional")
#if os(iOS)
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .textFieldStyle(.plain)
                .padding(.leading, 12)
                .padding(.vertical, 12)
#else
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
#endif
                .onSubmit { focusedField = nil }

                Button {
                    isAPIKeyVisible.toggle()
                    focusedField = .apiKey
                } label: {
                    Image(systemName: isAPIKeyVisible ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isAPIKeyVisible
                    ? String(localized: "Hide API Key")
                    : String(localized: "Show API Key"))
            }
#if os(iOS)
            .background(.background.secondary, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(focusedField == .apiKey ? Color.appAccent : Color.clear, lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
#endif

            Text("Leave this empty if your server doesn't require an API key.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var connectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                focusedField = nil
                onEvent(.testConnectionTapped)
            } label: {
                Label(state.connectionStatus == .testing
                    ? String(localized: "Testing...")
                    : String(localized: "Test Connection"), systemImage: "bolt.horizontal")
                    .font(.subheadline.weight(.medium))
#if os(iOS)
                    .frame(minHeight: 44)
#endif
            }
#if os(macOS)
            .buttonStyle(.bordered)
#else
            .buttonStyle(.glass)
#endif
            .controlSize(.large)
            .disabled(state.serverURL.isEmpty || state.connectionStatus == .testing)

            VStack(alignment: .leading, spacing: 12) {
                connectionStatus
                if state.showLiteLLMHint {
                    Label(
                        "Optimised for LiteLLM. Any OpenAI-compatible server also works.",
                        systemImage: "info.circle"
                    )
                    .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
        }
    }

    @ViewBuilder
    var connectionStatus: some View {
        switch state.connectionStatus {
        case .idle:
            Text("Test your connection to enable Continue.")
                .foregroundStyle(.secondary)
        case .testing:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
                Text("Checking your server...")
                    .foregroundStyle(.secondary)
            }
        case .success:
            Label("Connection successful. Ready to continue.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let message):
            Label {
                Text(message)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(.red)
            .accessibilityFocused($isErrorFocused)
        }
    }
}

#Preview("Server configuration") {
    ScrollView {
        OnboardingServerConfigurationView(
            serverURL: .constant(""),
            apiKey: .constant(""),
            isAPIKeyVisible: .constant(false),
            state: .init(currentStep: .serverConfiguration),
            onEvent: { _ in }
        )
        .padding(24)
    }
}

#Preview("Connection error, large text") {
    ScrollView {
        OnboardingServerConfigurationView(
            serverURL: .constant("https://server.example.com"),
            apiKey: .constant(""),
            isAPIKeyVisible: .constant(false),
            state: .init(
                currentStep: .serverConfiguration,
                serverURL: "https://server.example.com",
                connectionStatus: .failure(String(
                    localized: "The server could not be reached. Check the URL and try again."
                ))
            ),
            onEvent: { _ in }
        )
        .padding(24)
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
