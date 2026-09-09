//
//  ChatInputBarView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 02/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI
import TipKit

struct ChatInputBarView: View {
    // MARK: - Properties

    @Binding var showImagePicker: Bool
    @Binding var showDocumentPicker: Bool
    @Binding var showCameraPicker: Bool

    let state: ChatInputBarState
    let onSend: (String) -> Void
    let onStopStreaming: () -> Void
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onCancelRecording: () -> Void
    let onWebSearchToggled: () -> Void
    let onMCPButtonTapped: () -> Void

    @State private var inputText = ""
    @State private var isPulsing = false
    @Binding var showActions: Bool
    @Binding var showImageFilePicker: Bool
    @ScaledMetric(relativeTo: .body) private var minimumEntryWidth: CGFloat = 200

    // MARK: - View

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                if let activeToolStatus {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.secondary)
                        Text(activeToolStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if let usage = state.contextUsage {
                    ChatContextUsageView(usage: usage)
                        .popoverTip(
                            usage.percentage >= 50 && !state.isStreaming
                                ? AppTips.contextUsage
                                : nil,
                            arrowEdge: .bottom
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, activeToolStatus == nil ? 10 : 4)
                        .padding(.bottom, 4)
                }

                ZStack {
                    if state.isRecording {
                        recordingBar
                            .transition(.asymmetric(
                                insertion: .push(from: .trailing).combined(with: .opacity),
                                removal: .push(from: .leading).combined(with: .opacity)
                            ))
                    } else if state.isTranscribing {
                        transcribingBar
                            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .center)))
                    } else {
                        normalBar
                            .transition(.asymmetric(
                                insertion: .push(from: .leading).combined(with: .opacity),
                                removal: .push(from: .trailing).combined(with: .opacity)
                            ))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .glassEffect(.regular, in: .rect(cornerRadius: 25))
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
        .animation(.spring(duration: 0.35), value: state.isRecording)
        .animation(.spring(duration: 0.35), value: state.isTranscribing)
        .animation(.easeInOut(duration: 0.2), value: state.isSearchingWeb)
        .animation(.easeInOut(duration: 0.2), value: state.activeToolCallIds)
        .onChange(of: state.inputRevision, initial: true) {
            inputText = state.inputText
        }
    }
}

// MARK: - Private

private extension ChatInputBarView {
    var activeToolStatus: String? {
        let activeToolNames = state.activeToolNamesById.values
        guard !activeToolNames.isEmpty else { return nil }
        if activeToolNames.count > 1 {
            return String(localized: "Running \(activeToolNames.count) tool calls...")
        }
        if state.isSearchingWeb {
            return String(localized: "Searching the web...")
        }
        guard let toolName = activeToolNames.first else { return nil }
        switch toolName {
        case "get_current_datetime":
            return String(localized: "Getting the current date and time...")
        case "save_memory":
            return String(localized: "Saving a memory...")
        case "delete_memory":
            return String(localized: "Deleting a memory...")
        default:
            break
        }
        let displayName = state.mcpToolDisplayNames[toolName]
            ?? MCPDisplayText.sanitize(
                toolName,
                fallback: String(localized: "External tool"),
                maximumLength: 160
            )
        return String(localized: "Running \(displayName)...")
    }

    // MARK: Bar states

    var normalBar: some View {
        ChatInputLayout(minimumEntryWidth: minimumEntryWidth) {
            HStack(spacing: 5) {
                if state.selectedModel?.mode != .imageGeneration {
                    Group {
                        actionsToggleButton

                        if showActions {
                            attachmentMenu
                                .transition(.scale.combined(with: .opacity))

                            webSearchButton
                                .transition(.scale.combined(with: .opacity))

                            mcpButton
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .disabled(state.isStreaming)
                }
            }
            .fixedSize()

            HStack(alignment: .bottom, spacing: 8) {
                TextField(
                    String(localized: "Message..."),
                    text: $inputText,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .textSelection(.enabled)
                .lineLimit(1...5)
#if os(iOS)
                .submitLabel(.send)
#endif
                .onSubmit(sendInput)
                .frame(maxWidth: .infinity, minHeight: 44)

                actionButton
            }
        }
    }

    var recordingBar: some View {
        HStack(spacing: 12) {
            recordingIndicator

            Text(timerText)
                .accessibilityLabel(String(localized: "Recording duration"))
                .accessibilityValue(timerText)
                .font(.body.monospacedDigit())
                .foregroundStyle(.primary)
                .contentTransition(.numericText())

            Spacer()

            Button { onCancelRecording() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Cancel Recording"))

            Button { onStopRecording() } label: {
                Image(systemName: "stop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Stop Recording"))
        }
        .onAppear { startPulse() }
        .onDisappear { isPulsing = false }
    }

    var transcribingBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .foregroundStyle(.secondary)

            Text(String(localized: "Transcribing..."))
                .foregroundStyle(.secondary)

            Spacer()

            ProgressView()
                .controlSize(.small)
                .tint(.secondary)
        }
        .frame(minHeight: 44)
    }

    // MARK: Recording indicator

    var recordingIndicator: some View {
        ZStack {
            Circle()
                .fill(.red.opacity(0.25))
                .frame(width: 28, height: 28)
                .scaleEffect(isPulsing ? 1.5 : 1.0)
                .opacity(isPulsing ? 0.0 : 0.8)

            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
        }
        .frame(width: 44, height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Recording"))
    }

    var timerText: String {
        let total = Int(state.recordingDuration)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: Normal bar subviews

    @ViewBuilder
    var attachmentMenu: some View {
        Menu {
#if os(iOS)
            Button {
                AppTips.chatAttachments.invalidate(reason: .actionPerformed)
                showCameraPicker = true
            } label: {
                Label(String(localized: "Camera"), systemImage: "camera")
            }
#endif
#if os(macOS)
            Button {
                AppTips.chatAttachments.invalidate(reason: .actionPerformed)
                showImageFilePicker = true
            } label: {
                Label(String(localized: "Image File..."), systemImage: "photo.badge.plus")
            }
#endif
            Button {
                AppTips.chatAttachments.invalidate(reason: .actionPerformed)
                showDocumentPicker = true
            } label: {
                Label(String(localized: "Document"), systemImage: "doc")
            }

            Button {
                AppTips.chatAttachments.invalidate(reason: .actionPerformed)
                showImagePicker = true
            } label: {
                Label(String(localized: "Photo Library"), systemImage: "photo.on.rectangle")
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add Attachment")
        .popoverTip(canShowInputTips ? AppTips.chatAttachments : nil, arrowEdge: .bottom)
    }

    var webSearchButton: some View {
        let modelSupportsWebSearch = state.selectedModel.map {
            $0.capabilities.contains(.functionCalling)
        } ?? false

        return Button {
            AppTips.webSearch.invalidate(reason: .actionPerformed)
            onWebSearchToggled()
        } label: {
            Image(systemName: state.isWebSearchEnabled ? "globe.badge.chevron.backward" : "globe")
                .font(.title2)
                .foregroundStyle(
                    webSearchColor(
                        enabled: state.isWebSearchEnabled,
                        supported: modelSupportsWebSearch,
                        configured: state.isWebSearchToolConfigured
                    )
                )
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .popoverTip(canShowWebSearchTip ? AppTips.webSearch : nil, arrowEdge: .bottom)
        .accessibilityLabel(
            state.isWebSearchEnabled
            ? String(localized: "Disable Web Search")
            : String(localized: "Enable Web Search")
        )
        .accessibilityValue(!state.isWebSearchToolConfigured
            ? String(localized: "Web search is not configured")
            : (!modelSupportsWebSearch ? String(localized: "Not supported by this model") : ""))
        .animation(.easeInOut(duration: 0.2), value: state.isWebSearchEnabled)
    }

    var actionsToggleButton: some View {
        let hasActive = state.isWebSearchEnabled || hasEnabledMCPTool
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                showActions.toggle()
            }
        } label: {
            ZStack {
                Image(systemName: showActions ? "xmark.circle" : "plus.circle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                if hasActive && !showActions {
                    Circle()
                        .fill(Color.appAccent)
                        .frame(width: 8, height: 8)
                        .offset(x: 10, y: -10)
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showActions
            ? String(localized: "Hide Actions")
            : String(localized: "Show Actions"))
        .accessibilityValue(hasActive && !showActions ? String(localized: "Tools enabled") : "")
    }

    @ViewBuilder
    var actionButton: some View {
        let hasText = !inputText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        let hasModel = state.selectedModel != nil
        let hasAttachments = state.hasPendingAttachments
        let hasTranscriptionModel = state.hasTranscriptionModel

        if state.isPreparingAttachment {
            ProgressView()
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(String(localized: "Preparing image"))
        } else if state.isStreaming {
            if (hasText || hasAttachments) && hasModel {
                sendButton
            } else {
                stopStreamingButton
            }
        } else {
            if (hasText || hasAttachments) && hasModel {
                sendButton
            } else if hasModel && hasTranscriptionModel {
                micButton
            }
        }
    }

    var stopStreamingButton: some View {
        Button { onStopStreaming() } label: {
            Image(systemName: "stop.circle.fill").font(.title2).foregroundStyle(.red)
                .frame(minWidth: 44, minHeight: 44).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Stop"))
        .transition(.scale.combined(with: .opacity))
    }

    var sendButton: some View {
        Button(action: sendInput) {
            Image(systemName: "arrow.up.circle.fill").font(.title2).foregroundStyle(Color.appAccent)
                .frame(minWidth: 44, minHeight: 44).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Send"))
        .transition(.scale.combined(with: .opacity))
    }

    var micButton: some View {
        Button { onStartRecording() } label: {
            Image(systemName: "mic.circle.fill").font(.title2).foregroundStyle(.secondary)
                .frame(minWidth: 44, minHeight: 44).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Record Audio"))
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: Actions

    func sendInput() {
        let text = inputText
        inputText = ""
        onSend(text)
    }

    func startPulse() {
        isPulsing = false
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
            isPulsing = true
        }
    }

    func webSearchColor(enabled: Bool, supported: Bool, configured: Bool) -> Color {
        guard configured && supported else { return .red }
        return enabled ? Color.appAccent : .secondary
    }

    var canShowInputTips: Bool {
        state.selectedModel != nil
            && !state.isStreaming
            && !state.isRecording
            && !state.isTranscribing
            && !state.isSearchingWeb
    }

    var canShowWebSearchTip: Bool {
        canShowInputTips
            && state.isWebSearchToolConfigured
            && state.selectedModel?.capabilities.contains(.functionCalling) == true
    }

}
