//
//  ServerChatIDHeaderSection.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 04/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct ServerChatIDHeaderSection: View {
    let headerName: String?
    let error: String?
    let onEvent: (SettingsViewModel.Event) -> Void

    var body: some View {
        Section {
            Toggle("Send Chat ID", isOn: Binding(
                get: { headerName != nil },
                set: { onEvent(.chatIDHeaderToggled($0)) }
            ))
            Text("Enable only if your server requires a conversation identifier in an HTTP header.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if headerName != nil {
                LabeledContent("Header name") {
                    TextField("Header name", text: Binding(
                        get: { headerName ?? "" },
                        set: { onEvent(.chatIDHeaderNameChanged($0)) }
                    ), prompt: Text("e.g., X-Conversation-ID"))
                    .labelsHidden()
                    .accessibilityLabel("Header name")
                    .autocorrectionDisabled()
#if os(iOS)
                    .textInputAutocapitalization(.never)
#endif
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text("Send Chat ID")
        } footer: {
            if headerName != nil {
                Text("""
                OpenClient automatically sends each chat's identifier in this header. Each chat has a different \
                identifier that stays the same when you reopen it. It is not sent when listing models or testing \
                the connection.
                """)
            }
        }
    }
}

#Preview {
    Form {
        ServerChatIDHeaderSection(headerName: "X-Conversation-ID", error: nil, onEvent: { _ in })
    }
}

#Preview("Empty header name") {
    Form {
        ServerChatIDHeaderSection(headerName: "", error: nil, onEvent: { _ in })
    }
    .formStyle(.grouped)
}
