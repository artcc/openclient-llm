//
//  ServerHTTPHeaderRow.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 02/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct ServerHTTPHeaderRow: View {
    @Binding var header: ServerHTTPHeader
    let isDuplicate: Bool
    let onDelete: () -> Void
    @State private var isValueVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                TextField("Name", text: $header.name, prompt: Text("Name"))
                    .labelsHidden()
                    .accessibilityLabel("Header name")
                    .textSelection(.enabled)
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete Header")
            }
            if let error = header.nameError {
                errorLabel(error)
            } else if isDuplicate {
                errorLabel(String(localized: "Header names must be unique, regardless of capitalization."))
            }
            HStack {
                Group {
                    if isValueVisible {
                        TextField("Value", text: $header.value, prompt: Text("Value"))
                    } else {
                        SecureField("Value", text: $header.value, prompt: Text("Value"))
                    }
                }
                .labelsHidden()
                .accessibilityLabel("Header value")
                .textSelection(.enabled)
                Button {
                    isValueVisible.toggle()
                } label: {
                    Image(systemName: isValueVisible ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isValueVisible ? String(localized: "Hide Value") : String(localized: "Show Value"))
            }
            if let error = header.valueError { errorLabel(error) }
        }
        .autocorrectionDisabled()
#if os(iOS)
        .textInputAutocapitalization(.never)
#endif
    }

    private func errorLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.caption)
            .foregroundStyle(.red)
    }
}
