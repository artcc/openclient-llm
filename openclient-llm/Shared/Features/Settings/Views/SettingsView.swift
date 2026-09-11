//
//  SettingsView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI
import TipKit
#if os(iOS)
import StoreKit
import SwiftUI
#endif
import VoticeSDK

struct SettingsView: View {
    // MARK: - Properties

    @Binding var requestedPresentation: SettingsPresentation?

    @State var viewModel = SettingsViewModel()
    @State var serverURL: String = ""
    @State var apiKey: String = ""
    @State var isAPIKeyVisible = false
    @State var isShowingVotice = false
    @State private var isShowingUserProfile = false
    @State private var isShowingMemory = false
    @State private var isShowingTools = false
    @State var isShowingCloudData = false
    @State var isShowingHelp = false
    @State var isShowingTipJar = false
    @State private var showResetAlert = false
    @State var mcpServerSheet: MCPServerInfo?
    @State var presentedWebURL: WebDestination?
    @State private var canShowMemoryTip = false
    @State private var shouldRequestReviewAfterSync = false
    @FocusState var focusedField: Field?
    @Environment(\.scenePhase) private var scenePhase
    let liteLLMHintText = String(localized: "Optimised for LiteLLM. Any OpenAI-compatible server also works.")
    private let settingsManager: SettingsManagerProtocol = SettingsManager()
    private let appReviewManager: AppReviewManagerProtocol = AppReviewManager()

    enum Field {
        case serverURL
        case apiKey
    }

    // MARK: - Init

    init(requestedPresentation: Binding<SettingsPresentation?> = .constant(nil)) {
        _requestedPresentation = requestedPresentation
    }

    // MARK: - View

    var body: some View {
#if os(iOS)
        NavigationStack {
            settingsContent
        }
#else
        settingsContent
#endif
    }

    func synchronizeAppData() {
        shouldRequestReviewAfterSync = true
        viewModel.send(.syncNowTapped)
    }
}

// MARK: - Private

private extension SettingsView {
    var settingsContent: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView()
                    .accessibilityLabel(String(localized: "Loading settings..."))
                    .tint(.secondary)
            case .loaded(let loadedState):
                loadedView(loadedState)
            }
        }
        .navigationTitle(String(localized: "Settings"))
        .sheet(item: $presentedWebURL) { destination in
            if let url = destination.url {
                WebContentView(title: destination.title, url: url)
            }
        }
        .sheet(isPresented: $isShowingVotice) {
            Votice.feedbackView()
        }
        .sheet(isPresented: $isShowingUserProfile) {
            UserProfileView()
#if os(macOS)
                .frame(width: 700, height: 500)
#endif
        }
        .sheet(isPresented: $isShowingMemory) {
            MemoryView()
#if os(macOS)
                .frame(width: 700, height: 500)
#endif
        }
        .sheet(isPresented: $isShowingCloudData) {
            cloudDataSheet
#if os(macOS)
                .frame(width: 700, height: 500)
#endif
        }
        .sheet(isPresented: $isShowingTools) {
            ToolsView()
#if os(macOS)
                .frame(width: 700, height: 600)
#endif
        }
        .sheet(isPresented: $isShowingHelp) {
            HelpView()
#if os(macOS)
                .frame(width: 700, height: 500)
#endif
        }
        .sheet(isPresented: $isShowingTipJar) {
            TipJarView()
#if os(macOS)
                .frame(width: 700, height: 500)
#endif
        }
        .task(id: requestedPresentation) {
            guard let requestedPresentation else { return }
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }

            switch requestedPresentation {
            case .feedback:
                isShowingVotice = true
            case .tipJar:
                isShowingTipJar = true
            }
            self.requestedPresentation = nil
        }
        .alert(
            String(localized: "Review iCloud Account"),
            isPresented: cloudAccountReviewBinding,
            actions: {
                Button(String(localized: "Merge and Enable Sync")) {
                    viewModel.send(.cloudAccountReviewConfirmed)
                }
                Button(String(localized: "Cancel"), role: .cancel) {
                    viewModel.send(.cloudAccountReviewCancelled)
                }
            },
            message: {
                Text(String(
                    localized: """
                    Your local data will be merged into the current iCloud account. \
                    Cancel to keep iCloud Sync disabled.
                    """
                ))
            }
        )
        .alert(
            String(localized: "Profile Sync Conflict"),
            isPresented: cloudSyncConflictBinding,
            actions: {
                Button(String(localized: "Use Local Data")) {
                    viewModel.send(.cloudSyncConflictResolved(keepLocal: true))
                }
                Button(String(localized: "Use iCloud Data")) {
                    viewModel.send(.cloudSyncConflictResolved(keepLocal: false))
                }
                Button(String(localized: "Cancel"), role: .cancel) {
                    viewModel.send(.cloudSyncConflictCancelled)
                }
            },
            message: {
                Text(String(
                    localized: """
                    Your local profile and iCloud profile have different content with the same revision. \
                    Which profile would you like to keep?
                    """
                ))
            }
        )
        .alert(
            String(localized: "Reset App Data"),
            isPresented: $showResetAlert
        ) {
            Button(String(localized: "Reset"), role: .destructive) {
                canShowMemoryTip = false
                viewModel.send(.resetConfirmed)
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(
                localized: "All local settings and credentials will be deleted. iCloud data will not be affected."
            ))
        }
        .task {
            viewModel.send(.viewAppeared)
            if case .loaded(let initialState) = viewModel.state {
                serverURL = initialState.serverURL
                apiKey = initialState.apiKey
            }
            canShowMemoryTip = settingsManager.getHasEnoughConversationsForMemoryTip()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                viewModel.send(.notificationStatusRefresh)
                viewModel.send(.cloudAvailabilityRefresh)
            }
        }
        .onChange(of: viewModel.state) { _, newState in
            if case .loaded(let loadedState) = newState {
                serverURL = loadedState.serverURL
                apiKey = loadedState.apiKey
                if viewModel.cloudSyncStatus != .synchronizing,
                   let result = loadedState.synchronizationResult,
                   !result.isSuccessful {
                    shouldRequestReviewAfterSync = false
                }
            }
        }
        .onDisappear(perform: requestReviewAfterSuccessfulSyncIfNeeded)
    }

    var cloudSyncConflictBinding: Binding<Bool> {
        Binding(
            get: {
                guard case .loaded(let loadedState) = viewModel.state else { return false }
                return loadedState.showCloudSyncConflictAlert
            },
            set: { newValue in
                if !newValue {
                    viewModel.send(.cloudSyncConflictCancelled)
                }
            }
        )
    }

    var cloudAccountReviewBinding: Binding<Bool> {
        Binding(
            get: {
                guard case .loaded(let loadedState) = viewModel.state else { return false }
                return loadedState.showCloudAccountReviewAlert
            },
            set: { newValue in
                if !newValue {
                    viewModel.send(.cloudAccountReviewDismissed)
                }
            }
        )
    }

    func loadedView(_ loadedState: SettingsViewModel.LoadedState) -> some View {
        VStack(spacing: 0) {
            Form {
                appIconSection(loadedState)
                serverSection(loadedState)
                cloudSyncSection(loadedState)
                personalizationSection()
                chatSection(loadedState)
                toolsSection
                webSearchSection(loadedState)
                mcpSection(loadedState)
                supportSection(loadedState)
                legalSection()
                dangerSection()
            }
#if os(iOS)
            .scrollDismissesKeyboard(.immediately)
#elseif os(macOS)
            .formStyle(.grouped)
#endif
        }
        .sheet(item: $mcpServerSheet) { server in
            mcpToolSheet(server: server, loadedState: loadedState)
#if os(macOS)
                .frame(width: 700, height: 500)
#endif
        }
    }

    func chatSection(_ loadedState: SettingsViewModel.LoadedState) -> some View {
        Section {
            Toggle(isOn: Binding(
                get: { loadedState.showTokenUsage },
                set: { viewModel.send(.showTokenUsageToggled($0)) }
            )) {
                Label(String(localized: "Show Token Usage"), systemImage: "number")
            }
#if os(iOS)
            Toggle(isOn: Binding(
                get: { loadedState.isPrivacyScreenEnabled },
                set: { viewModel.send(.privacyScreenToggled($0)) }
            )) {
                Label(String(localized: "Hide Content in App Switcher"), systemImage: "lock.shield")
            }
#endif
            switch loadedState.notificationPermissionStatus {
            case .authorized:
                Label(String(localized: "Notifications enabled"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .denied:
                Label(String(localized: "Notifications disabled"), systemImage: "bell.slash")
                    .foregroundStyle(.secondary)
#if os(iOS)
                Button {
                    guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                } label: {
                    settingsDestinationLabel("Open Settings", systemImage: "gearshape", isExternal: true)
                }
                .buttonStyle(.plain)
#endif
            case .notDetermined:
                Label(String(localized: "Notifications not authorized"), systemImage: "bell.badge.slash")
                    .foregroundStyle(.secondary)
                enableNotificationsButton()
            }
        } header: {
            Text(String(localized: "Chat"))
        } footer: {
            Text(String(localized: "Sent when a response finishes while the app is in the background."))
        }
    }

    func personalizationSection() -> some View {
        Section {
            Button {
                isShowingUserProfile = true
            } label: {
                settingsDestinationLabel("Personal Context", systemImage: "person.text.rectangle")
            }
            .buttonStyle(.plain)

            Button {
                AppTips.memory.invalidate(reason: .actionPerformed)
                isShowingMemory = true
            } label: {
                settingsDestinationLabel("Memory", systemImage: "brain.head.profile")
            }
            .buttonStyle(.plain)
            .popoverTip(canShowMemoryTip ? AppTips.memory : nil)
        } header: {
            Text(String(localized: "Personalization"))
        } footer: {
            Text(String(localized: "Configure your personal context and memory items to personalise model responses."))
        }
    }

    var toolsSection: some View {
        Section {
            Button {
                isShowingTools = true
            } label: {
                settingsDestinationLabel("Tools", systemImage: "wrench.and.screwdriver")
            }
            .buttonStyle(.plain)
        } header: {
            Text(String(localized: "Tools"))
        } footer: {
            Text(String(localized: "Manage the built-in tools OpenClient makes available to the assistant."))
        }
    }

    func requestReviewAfterSuccessfulSyncIfNeeded() {
        guard shouldRequestReviewAfterSync else { return }
        shouldRequestReviewAfterSync = false
        appReviewManager.requestReview()
    }

    func enableNotificationsButton() -> some View {
        Button {
            viewModel.send(.requestNotificationPermissionTapped)
        } label: {
            Label(String(localized: "Enable Notifications"), systemImage: "bell")
        }
#if os(macOS)
        .buttonStyle(.bordered)
#else
        .buttonStyle(.automatic)
        .tint(.primary)
#endif
    }

    func dangerSection() -> some View {
        Section {
            Button {
                showResetAlert = true
            } label: {
                Label(String(localized: "Reset App Data"), systemImage: "trash")
                    .foregroundStyle(.red)
            }
#if os(macOS)
            .buttonStyle(.bordered)
#else
            .buttonStyle(.plain)
#endif
            if let resetErrorMessage = currentLoadedState?.resetErrorMessage {
                Label(resetErrorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text(String(localized: "App Data"))
        } footer: {
            Text(String(localized: "Deletes all local settings and credentials. iCloud data will not be affected."))
        }
    }

    var currentLoadedState: SettingsViewModel.LoadedState? {
        guard case .loaded(let loadedState) = viewModel.state else { return nil }
        return loadedState
    }
}

#Preview {
    SettingsView()
}
