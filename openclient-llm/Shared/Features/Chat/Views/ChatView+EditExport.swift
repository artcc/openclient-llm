//
//  ChatView+EditExport.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 03/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

// MARK: - Phase 6: Regenerate, Edit, Export helpers

extension ChatView {
    @ViewBuilder
    func regenerateBar(
        _ loadedState: ChatViewModel.LoadedState,
        viewModel: ChatViewModel
    ) -> some View {
        if !loadedState.isStreaming,
           !loadedState.messages.isEmpty,
           loadedState.messages.last?.role == .assistant,
           loadedState.conversation != nil {
            Button {
                viewModel.send(.regenerateLastResponse)
            } label: {
                Label(String(localized: "Regenerate Response"), systemImage: "arrow.clockwise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 6)
        }
    }

    func editMessageSheet(
        _ message: ChatMessage,
        viewModel: ChatViewModel,
        editingMessage: Binding<ChatMessage?>,
        editingMessageText: Binding<String>
    ) -> some View {
        NavigationStack {
            TextEditor(text: editingMessageText)
                .accessibilityLabel(String(localized: "Message"))
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .navigationTitle(String(localized: "Edit Message"))
#if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
#endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel")) {
                            editingMessage.wrappedValue = nil
                            editingMessageText.wrappedValue = ""
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Resend")) {
                            let content = editingMessageText.wrappedValue
                            viewModel.send(.editMessage(id: message.id, newContent: content))
                            editingMessage.wrappedValue = nil
                            editingMessageText.wrappedValue = ""
                        }
                        .disabled(
                            editingMessageText.wrappedValue
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                        )
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .scrollDismissesKeyboard(.interactively)
    }

}
