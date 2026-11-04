//
//  ServerAdvancedSettingsView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 02/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct ServerAdvancedSettingsView: View {
    let headers: [ServerHTTPHeader]
    var chatIDHeaderName: String?
    let onEvent: (SettingsViewModel.Event) -> Void
    @Binding var isPresented: Bool

    var body: some View {
#if os(macOS)
        VStack(spacing: 0) {
            HStack {
                cancelButton
                    .buttonStyle(.plain)
                Spacer()
                Text("Advanced Server Settings")
                    .font(.headline)
                Spacer()
                doneButton
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
            form
        }
        .frame(width: 700, height: 500)
#else
        NavigationStack {
            form
                .navigationTitle("Advanced Server Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { cancelButton }
                    ToolbarItem(placement: .confirmationAction) { doneButton }
                }
        }
#endif
    }
}

private extension ServerAdvancedSettingsView {
    var form: some View {
        Form {
            ServerChatIDHeaderSection(
                headerName: chatIDHeaderName,
                error: ServerHTTPHeader.chatIDHeaderNameError(chatIDHeaderName, in: headers),
                onEvent: onEvent
            )
            Section {
                if headers.isEmpty {
                    Text("No custom headers configured.")
                        .foregroundStyle(.secondary)
                }
                ForEach(headers) { header in
                    ServerHTTPHeaderRow(
                        header: Binding(
                            get: { headers.first(where: { $0.id == header.id }) ?? header },
                            set: { onEvent(.customHeaderChanged($0)) }
                        ),
                        isDuplicate: headers.filter { $0.name.lowercased() == header.name.lowercased() }.count > 1
                            || header.name.lowercased() == chatIDHeaderName?.lowercased(),
                        onDelete: { onEvent(.customHeaderRemoved(header.id)) }
                    )
                }
                Button {
                    onEvent(.customHeaderAdded)
                } label: {
                    Label("Add Header", systemImage: "plus")
                }
                .disabled(headers.count + (chatIDHeaderName == nil ? 0 : 1) >= ServerHTTPHeader.maximumCount)
                if let error = ServerHTTPHeader.validationError(in: headers, chatIDHeaderName: chatIDHeaderName) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Custom Headers")
            } footer: {
                Text("Sent with requests to your configured server. Tap Done, then Save in Server to save changes.")
            }
        }
#if os(macOS)
        .formStyle(.grouped)
#else
        .scrollDismissesKeyboard(.interactively)
#endif
    }

    var cancelButton: some View {
        Button("Cancel", role: .cancel) {
            onEvent(.advancedServerSettingsCancelled)
            isPresented = false
        }
        .keyboardShortcut(.cancelAction)
    }

    var doneButton: some View {
        Button("Done") {
            onEvent(.advancedServerSettingsApplied)
            isPresented = false
        }
        .disabled(ServerHTTPHeader.validationError(in: headers, chatIDHeaderName: chatIDHeaderName) != nil)
        .keyboardShortcut(.defaultAction)
    }
}

#Preview("Empty") {
    ServerAdvancedSettingsView(
        headers: [],
        onEvent: { _ in },
        isPresented: .constant(true)
    )
}

#Preview("Custom Headers") {
    ServerAdvancedSettingsView(
        headers: [
            ServerHTTPHeader(name: "x-opencode-session", value: "example-session"),
            ServerHTTPHeader(name: "User-Agent", value: "OpenClient")
        ],
        onEvent: { _ in },
        isPresented: .constant(true)
    )
}

#Preview("Chat ID") {
    ServerAdvancedSettingsView(
        headers: [],
        chatIDHeaderName: "X-Conversation-ID",
        onEvent: { _ in },
        isPresented: .constant(true)
    )
}
