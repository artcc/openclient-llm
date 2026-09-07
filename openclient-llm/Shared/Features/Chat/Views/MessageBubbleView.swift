//
//  MessageBubbleView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI
import TipKit
#if canImport(UIKit)
import SwiftUI
#elseif canImport(AppKit)
import AppKit
#endif

struct MessageBubbleView: View {
    // MARK: - Properties

    let message: ChatMessage
    var isStreaming: Bool = false
    var isSpeaking: Bool = false
    var hasTTS: Bool = false
    var showTokenUsage: Bool = true
    var isLastMessage: Bool = false
    var isRunningTool: Bool = false
    var showsMessageActionsTip: Bool = false
    var onSpeakTapped: (() -> Void)?
    var onStopSpeakingTapped: (() -> Void)?
    var onEditTapped: (() -> Void)?
    var onRegenerateTapped: (() -> Void)?
    var onForkTapped: (() -> Void)?
    var onFavouriteTapped: (() -> Void)?
    var onLayoutChanged: (() -> Void)?
    @State var cursorVisible: Bool = false
    @State var renderedMarkdown = RenderedMarkdown.empty
    @State private var reasoningDisclosureState = ReasoningDisclosureState()
#if os(iOS)
    @State private var isShowingTextSelection = false
#endif

    // MARK: - View

    var body: some View {
        switch message.role {
        case .user:
            userMessageLayout
        case .assistant, .system:
            assistantMessageLayout
        case .tool:
            EmptyView()
        }
    }
}

// MARK: - Private

private extension MessageBubbleView {
    var userMessageLayout: some View {
        HStack {
            Spacer(minLength: 60)

            VStack(alignment: .trailing, spacing: 4) {
                if !message.attachments.isEmpty {
                    attachmentsView
                }
                Text(message.content)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .glassEffect(
                        .regular.tint(Color.appAccent),
                        in: .rect(cornerRadius: 18)
                    )
                HStack(spacing: 4) {
                    timestampLabel
                    messageActionsMenu
                }
                .padding(.trailing, 4)
            }
        }
    }

    var assistantMessageLayout: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundStyle(Color.appAccent)
                .frame(width: 28, height: 28)
                .glassEffect(.regular, in: .circle)

            VStack(alignment: .leading, spacing: 8) {
                if !message.attachments.isEmpty {
                    attachmentsView
                }

                if let reasoning = message.reasoningContent, !reasoning.isEmpty {
                    thinkingDisclosureView(reasoning)
                }

                if message.content.isEmpty && isStreaming && (message.reasoningContent ?? "").isEmpty {
                    thinkingIndicator
                } else if !message.content.isEmpty {
                    if isStreaming
                        || renderedMarkdown.source != message.content
                        || renderedMarkdown.blocks.isEmpty {
                        unformattedMessageTextView
                    } else {
                        blocksView
                    }
                }

                if !message.content.isEmpty || !message.attachments.isEmpty {
                    HStack(spacing: 8) {
                        if let usage = message.tokenUsage, !isStreaming, showTokenUsage {
                            tokenUsageLabel(usage)
                        }

                        Spacer(minLength: 8)

                        timestampLabel
                        messageActionsMenu
                    }
                }

                if let results = message.webSearchResults, !results.isEmpty, !isStreaming {
                    WebSearchSourcesView(results: results)
                }

                if !isStreaming && !message.content.isEmpty && message.role == .assistant && hasTTS {
                    speakButton
                }

                if !isStreaming, !message.content.isEmpty, isLastMessage, let onRegenerateTapped {
                    Button(action: onRegenerateTapped) {
                        Label(String(localized: "Regenerate Response"), systemImage: "arrow.clockwise")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            .frame(minHeight: 28, alignment: .center)

            Spacer(minLength: 0)
        }
        .onAppear {
            reasoningDisclosureState.viewAppeared(
                isStreaming: isStreaming,
                hasReasoning: !(message.reasoningContent ?? "").isEmpty,
                hasAnswer: !message.content.isEmpty
            )
        }
        .onChange(of: message.content) {
            if !message.content.isEmpty {
                reasoningDisclosureState.answerReceived(isStreaming: isStreaming)
            }
        }
        .onChange(of: message.reasoningContent) {
            if !(message.reasoningContent ?? "").isEmpty {
                reasoningDisclosureState.reasoningReceived(isStreaming: isStreaming)
            }
        }
        .onChange(of: isRunningTool) { _, isRunning in
            if isRunning {
                reasoningDisclosureState.toolStarted()
            }
        }
        .task(id: isStreaming) {
            guard isStreaming else {
                cursorVisible = false
                withAnimation(.easeInOut(duration: 0.4)) {
                    reasoningDisclosureState.streamingEnded()
                }
                return
            }
            reasoningDisclosureState.viewAppeared(
                isStreaming: true,
                hasReasoning: !(message.reasoningContent ?? "").isEmpty,
                hasAnswer: !message.content.isEmpty
            )
        }
        .task(id: shouldBlinkStreamingIndicator) {
            guard shouldBlinkStreamingIndicator else {
                cursorVisible = false
                return
            }
            while !Task.isCancelled {
                cursorVisible.toggle()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        .task(id: isStreaming ? nil : message.content) {
            await renderMarkdownIfNeeded()
        }
    }

    // MARK: - Attachments

    @ViewBuilder
    var attachmentsView: some View {
        HStack(spacing: 8) {
            ForEach(message.attachments) { attachment in
                switch attachment.type {
                case .image:
                    imageThumbnail(attachment)
                case .pdf:
                    documentCard(attachment)
                }
            }
        }
    }

    @ViewBuilder
    func imageThumbnail(_ attachment: ChatMessage.Attachment) -> some View {
        AttachmentImageView(attachment: attachment)
    }

    func documentCard(_ attachment: ChatMessage.Attachment) -> some View {
        HStack(spacing: 8) {
            Image(systemName: attachment.type == .image ? "photo" : "doc.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Text(attachment.type == .image
                     ? String(localized: "Image")
                     : String(localized: "PDF Document"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    // MARK: - Message Actions

    var messageActionsMenu: some View {
        Menu {
            messageContextMenu(message.content)
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Message actions"))
        .popoverTip(
            showsMessageActionsTip
                ? AppTips.messageActions
                : nil
        )
#if os(iOS)
        .sheet(isPresented: $isShowingTextSelection) {
            MessageTextSelectionView(text: message.content)
        }
#endif
    }

    @ViewBuilder
    func messageContextMenu(_ content: String) -> some View {
        commonMessageActions(content)

        if message.role == .user, let onEditTapped {
            Divider()
            Button {
                AppTips.messageActions.invalidate(reason: .actionPerformed)
                onEditTapped()
            } label: {
                Label(String(localized: "Edit & Resend"), systemImage: "pencil")
            }
        }

        if message.role == .assistant, isLastMessage, !isStreaming, let onRegenerateTapped {
            Divider()
            Button {
                AppTips.messageActions.invalidate(reason: .actionPerformed)
                onRegenerateTapped()
            } label: {
                Label(String(localized: "Regenerate Response"), systemImage: "arrow.clockwise")
            }
        }

        additionalMessageActions
    }

    @ViewBuilder
    func commonMessageActions(_ content: String) -> some View {
#if os(iOS)
        Button {
            AppTips.messageActions.invalidate(reason: .actionPerformed)
            isShowingTextSelection = true
        } label: {
            Label(String(localized: "Select Text"), systemImage: "text.cursor")
        }
#endif

        Button {
            AppTips.messageActions.invalidate(reason: .actionPerformed)
            copyToClipboard(content)
        } label: {
            Label(String(localized: "Copy Message"), systemImage: "doc.on.doc")
        }

        ShareLink(
            item: content,
            subject: Text(String(localized: "Chat Message")),
            message: Text(content)
        ) {
            Label(String(localized: "Share"), systemImage: "square.and.arrow.up")
        }
    }

    @ViewBuilder
    var additionalMessageActions: some View {
        if let onForkTapped {
            Button {
                AppTips.messageActions.invalidate(reason: .actionPerformed)
                onForkTapped()
            } label: {
                Label(String(localized: "Fork from here"), systemImage: "arrow.branch")
            }
        }

        if let onFavouriteTapped {
            Divider()
            Button {
                AppTips.messageActions.invalidate(reason: .actionPerformed)
                onFavouriteTapped()
            } label: {
                Label(
                    message.isFavourite
                        ? String(localized: "Remove from Favourites")
                        : String(localized: "Add to Favourites"),
                    systemImage: message.isFavourite ? "star.slash" : "star"
                )
            }
        }
    }

    func copyToClipboard(_ text: String) {
#if os(iOS)
        UIPasteboard.general.string = text
#elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
#endif
    }

    var thinkingIndicator: some View {
        Text(String(localized: "Thinking..."))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    func thinkingDisclosureView(_ reasoning: String) -> some View {
        DisclosureGroup(isExpanded: thinkingExpansionBinding) {
            ScrollView {
                Text(reasoning)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
            }
            .frame(maxHeight: 200)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "brain")
                    .font(.system(size: 11))
                Text(String(localized: "Thinking"))
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(isActivelyReasoning ? AnyShapeStyle(Color.appAccent) : AnyShapeStyle(.secondary))
            .opacity(isActivelyReasoning ? (cursorVisible ? 1.0 : 0.5) : 0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    var thinkingExpansionBinding: Binding<Bool> {
        Binding(
            get: { reasoningDisclosureState.isExpanded },
            set: { reasoningDisclosureState.userToggledExpansion($0) }
        )
    }

    var isActivelyReasoning: Bool {
        reasoningDisclosureState.phase == .reasoning
    }

    var shouldBlinkStreamingIndicator: Bool {
        isStreaming && (!message.content.isEmpty || !(message.reasoningContent ?? "").isEmpty)
    }

    func tokenUsageLabel(_ usage: TokenUsage) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "number")
                .font(.system(size: 9))
            Text(String(localized: "\(usage.totalTokens) tokens"))
                .font(.caption2)
        }
        .foregroundStyle(.tertiary)
    }

    var timestampLabel: some View {
        Text(message.timestamp, style: .time)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .accessibilityLabel(message.timestamp.formatted(date: .long, time: .shortened))
    }

    var speakButton: some View {
        Button {
            if isSpeaking {
                onStopSpeakingTapped?()
            } else {
                onSpeakTapped?()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isSpeaking ? "stop.circle.fill" : "speaker.wave.2")
                    .font(.system(size: 10))
                Text(isSpeaking
                     ? String(localized: "Stop")
                     : String(localized: "Listen"))
                    .font(.caption2)
            }
            .foregroundStyle(isSpeaking ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Image Actions

    @ViewBuilder
    func imageSaveContextMenu(_ attachment: ChatMessage.Attachment) -> some View {
        EmptyView() // Context menu is handled inside AttachmentImageView
    }
}
