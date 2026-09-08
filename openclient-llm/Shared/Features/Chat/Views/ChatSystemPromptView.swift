//
//  ChatSystemPromptView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 31/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct ChatSystemPromptView: View {
    // MARK: - Properties

    var viewModel: ChatViewModel
    @Binding var isPresented: Bool

    @State private var showTemplateLibrary = false

    // MARK: - View

    var body: some View {
        Group {
            #if os(macOS)
            macOSBody
            #else
            NavigationStack {
                editor
                    .navigationTitle(String(localized: "System Prompt"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(String(localized: "Done")) {
                                isPresented = false
                            }
                        }
                    }
            }
            #endif
        }
        #if os(macOS)
        .frame(width: 500, height: 460)
        #endif
        .sheet(isPresented: $showTemplateLibrary) {
            PromptTemplatesView { template in
                viewModel.send(.systemPromptChanged(template.content))
            }
        }
    }
}

// MARK: - Private

private extension ChatSystemPromptView {
    #if os(macOS)
    var macOSBody: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()

                Text(String(localized: "System Prompt"))
                    .font(.headline)

                Spacer()

                Button(String(localized: "Done")) {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            editor
        }
    }
    #endif

    @ViewBuilder
    var editor: some View {
        if case .loaded(let loadedState) = viewModel.state {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    Text(String(localized: "Set instructions for the assistant's behavior in this conversation."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        showTemplateLibrary = true
                    } label: {
                        Label(String(localized: "Browse Library"), systemImage: "books.vertical")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal)

                TextEditor(text: Binding(
                    get: { loadedState.systemPrompt },
                    set: { viewModel.send(.systemPromptChanged($0)) }
                ))
                .accessibilityLabel(String(localized: "System Prompt"))
                .font(.body)
#if os(macOS)
                .frame(minHeight: 200)
#endif
                .padding(.horizontal)
            }
            .padding(.top)
        }
    }
}

#Preview {
    ChatSystemPromptView(
        viewModel: ChatViewModel(),
        isPresented: .constant(true)
    )
}
