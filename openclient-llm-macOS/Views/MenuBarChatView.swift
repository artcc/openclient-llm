//
//  MenuBarChatView.swift
//  openclient-llm-macOS
//
//  Created by Arturo Carretero Calvo on 10/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

// MARK: - View

struct MenuBarChatView: View {
    // MARK: - Properties

    var onOpenInApp: (Conversation?) -> Void
    var onAuthorizationStateChanged: (Bool) -> Void = { _ in }

    @State private var chatId = UUID()
    @State private var viewModel = ChatViewModel()
    @State private var isOpeningInApp = false

    // MARK: - View

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            ChatView(
                isMenuBarPresentation: true,
                presentsMCPAuthorization: false,
                viewModel: viewModel
            )
                .id(chatId)
                .allowsHitTesting(!isOpeningInApp)
        }
        .frame(width: 380, height: 540)
        .mcpToolAuthorizationPresentation(viewModel: viewModel, compact: true)
        .onChange(of: viewModel.mcpAuthorizationCoordinator.pendingBatch != nil, initial: true) { _, isPending in
            onAuthorizationStateChanged(isPending)
        }
    }
}

// MARK: - Private

private extension MenuBarChatView {
    var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(.secondary)
            Text(String(localized: "OpenClient"))
                .font(.headline)
            Spacer()
            Button {
                openInApp()
            } label: {
                HStack(spacing: 4) {
                    if isOpeningInApp {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Label(String(localized: "Open in App"), systemImage: "arrow.up.forward.app")
                        .font(.caption)
                        .labelStyle(.titleAndIcon)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(isOpeningInApp || !viewModel.canPrepareForAppHandoff)
            .accessibilityValue(isOpeningInApp ? String(localized: "Opening in app") : "")
            .help(
                !viewModel.canPrepareForAppHandoff
                ? String(localized: "Finish or clear the current input before opening it in the app.")
                : String(localized: "Open in App")
            )
            Button {
                viewModel.send(.stopStreamingTapped)
                viewModel = ChatViewModel()
                chatId = UUID()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(isOpeningInApp)
            .accessibilityLabel(String(localized: "New Chat"))
            .help(String(localized: "New Chat"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    func openInApp() {
        guard !isOpeningInApp, viewModel.canPrepareForAppHandoff else { return }
        isOpeningInApp = true
        Task {
            switch await viewModel.prepareForAppHandoff() {
            case .newChat:
                completeAppHandoff(conversation: nil)
            case .conversation(let conversation):
                completeAppHandoff(conversation: conversation)
            case .draftPending, .persistenceFailed:
                isOpeningInApp = false
            }
        }
    }

    func completeAppHandoff(conversation: Conversation?) {
        onOpenInApp(conversation)
        viewModel = ChatViewModel()
        chatId = UUID()
        isOpeningInApp = false
    }
}

// MARK: - Preview

#Preview {
    MenuBarChatView(onOpenInApp: { _ in })
        .frame(width: 380, height: 540)
}
