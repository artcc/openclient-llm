//
//  LaunchView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct LaunchView: View {
    // MARK: - Properties

    @Environment(\.openURL) private var openURL
    @State private var viewModel = LaunchViewModel()
    @State private var pendingSpotlightConversationID: UUID?

    // MARK: - View

    var body: some View {
        ZStack {
#if os(macOS)
            macOSBody
#else
            iOSBody
#endif
        }
        .onContinueUserActivity(SpotlightConstants.activityType) { activity in
            guard let identifier = activity.userInfo?[SpotlightConstants.activityIdentifierKey] as? String,
                  let id = UUID(uuidString: identifier) else { return }
            viewModel.send(.externalEntryRequested)
            pendingSpotlightConversationID = id
        }
        .task {
            viewModel.send(.viewAppeared)
        }
        .onDisappear { viewModel.send(.viewDisappeared) }
        .alert(
            String(localized: "Update available"),
            isPresented: availableUpdateAlertBinding
        ) {
            Button(String(localized: "Not Now"), role: .cancel) {
                viewModel.send(.availableUpdateDismissed)
            }
            Button(String(localized: "Update")) {
                if let update = viewModel.availableUpdate {
                    openURL(update.updateURL)
                }
                viewModel.send(.availableUpdateDismissed)
            }
        } message: {
            Text(availableUpdateMessage)
        }
    }

    // MARK: - iOS

    var iOSBody: some View {
        Group {
            switch viewModel.state {
            case .loading:
                AppSplashView(showsLoadingIndicator: true)
            case .onboarding:
                OnboardingView {
                    withAnimation(.smooth) {
                        viewModel.send(.onboardingCompleted)
                    }
                }
            case .home:
                homeView
            case .maintenance:
                MaintenanceView()
            case .forceUpdate(let update):
                ForceUpdateView(update: update)
            case .resetFailed:
                resetFailureView
            }
        }
    }

    // MARK: - macOS

    var macOSBody: some View {
        ZStack {
            homeView
                .allowsHitTesting(viewModel.state == .home)
                .accessibilityHidden(viewModel.state != .home)
#if os(macOS)
                .toolbar(shouldCoverMacOSHome ? .hidden : .automatic, for: .windowToolbar)
#endif

#if os(macOS)
            if shouldCoverMacOSHome {
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()
            }
#endif

            if viewModel.state == .loading {
                AppSplashView(showsLoadingIndicator: true, backgroundMaterial: .ultraThickMaterial)
                    .transition(.opacity)
            }

            if viewModel.state == .onboarding {
                OnboardingView {
                    viewModel.send(.onboardingCompleted)
                }
                .transition(.opacity)
            }

            if viewModel.state == .maintenance {
                MaintenanceView()
                    .transition(.opacity)
            }

            if case .forceUpdate(let update) = viewModel.state {
                ForceUpdateView(update: update)
                    .transition(.opacity)
            }

            if viewModel.state == .resetFailed {
                resetFailureView
                    .transition(.opacity)
            }
        }
        .animation(.smooth, value: viewModel.state)
    }
}

// MARK: - Private

private extension LaunchView {
    var homeView: some View {
        HomeView(
            remoteBanner: viewModel.remoteBanner,
            onRemoteBannerDismiss: { viewModel.send(.remoteBannerDismissed) },
            remoteWhatsNew: Binding(
                get: { viewModel.remoteWhatsNew },
                set: { if $0 == nil { viewModel.send(.remoteWhatsNewDismissed) } }
            ),
            pendingSpotlightConversationID: Binding(
                get: { viewModel.state == .home ? pendingSpotlightConversationID : nil },
                set: { pendingSpotlightConversationID = $0 }
            ),
            onExternalEntry: { viewModel.send(.externalEntryRequested) },
            onNewsAppeared: { viewModel.send(.remoteWhatsNewAppeared) }
        )
    }

    var resetFailureView: some View {
        ContentUnavailableView {
            Label(String(localized: "App Data Reset Failed"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(String(localized: "Some local data could not be reset. No remaining data was discarded."))
        } actions: {
            Button(String(localized: "Retry")) {
                viewModel.send(.resetRetried)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    var availableUpdateAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.state == .home && viewModel.availableUpdate != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.send(.availableUpdateDismissed)
                }
            }
        )
    }

    var availableUpdateMessage: String {
        guard let version = viewModel.availableUpdate?.latestVersion else { return "" }
        return String(
            localized: "OpenClient version \(version) is available. Would you like to update now?"
        )
    }

    var shouldCoverMacOSHome: Bool {
        switch viewModel.state {
        case .loading, .onboarding, .maintenance, .forceUpdate, .resetFailed:
            true
        case .home:
            false
        }
    }
}

#Preview("Onboarding not completed") {
    LaunchView()
}
