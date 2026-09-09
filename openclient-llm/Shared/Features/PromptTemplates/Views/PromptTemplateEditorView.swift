//
//  PromptTemplateEditorView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 04/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct PromptTemplateEditorView: View {
    // MARK: - Properties

    let editingTemplate: PromptTemplate?
    let onSave: (String, String) -> Void

    @State private var title: String = ""
    @State private var content: String = ""

    @Environment(\.dismiss) private var dismiss

    // MARK: - View

    var body: some View {
        Group {
            #if os(macOS)
            macOSBody
            #else
            NavigationStack {
                editor
                    .navigationTitle(editingTemplate == nil
                        ? String(localized: "New Template")
                        : String(localized: "Edit Template"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(String(localized: "Cancel")) {
                                dismiss()
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(String(localized: "Save")) {
                                onSave(title, content)
                                dismiss()
                            }
                            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty
                                || content.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
            }
            #endif
        }
        .onAppear {
            if let template = editingTemplate {
                title = template.title
                content = template.content
            }
        }
        #if os(macOS)
        .frame(width: 500, height: 460)
        #endif
    }
}

// MARK: - Private

private extension PromptTemplateEditorView {
    #if os(macOS)
    var macOSBody: some View {
        VStack(spacing: 0) {
            HStack {
                Button(String(localized: "Cancel")) {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Text(editingTemplate == nil
                    ? String(localized: "New Template")
                    : String(localized: "Edit Template"))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                Button(String(localized: "Save")) {
                    onSave(title, content)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty
                    || content.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            editor
        }
    }
    #endif

    var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Title"))
                    .font(.headline)
                    .padding(.horizontal)

                TextField(String(localized: "e.g. Coding Assistant"), text: $title)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(String(localized: "Title"))
                    .padding(.horizontal)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Prompt"))
                    .font(.headline)
                    .padding(.horizontal)

                TextEditor(text: $content)
                    .font(.body)
                    .accessibilityLabel(String(localized: "Prompt"))
                    .frame(minHeight: 160, maxHeight: .infinity)
                    #if os(macOS)
                    .frame(minHeight: 200)
                    #endif
                    .padding(.horizontal)
            }
        }
        .padding(.vertical)
    }
}

#Preview {
    PromptTemplateEditorView(editingTemplate: nil) { _, _ in }
}
