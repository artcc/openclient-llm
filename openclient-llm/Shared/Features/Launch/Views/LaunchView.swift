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
    @State private var presentedBannerWebDestination: BannerWebDestination?

    // MARK: - View

    var body: some View {
        Group {
#if os(macOS)
            macOSBody
#else
            iOSBody
#endif
        }
        .task {
            viewModel.send(.viewAppeared)
        }
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
        .sheet(item: $presentedBannerWebDestination) { destination in
            WebContentView(title: destination.title, url: destination.url)
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
            onRemoteBannerDismiss: {
                viewModel.send(.remoteBannerDismissed)
            },
            onRemoteBannerAction: handleRemoteBannerAction
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

    func handleRemoteBannerAction() {
        guard let remoteBanner = viewModel.remoteBanner else { return }

        if remoteBanner.item.action == .openURL,
           let url = URL(string: remoteBanner.item.url),
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme) {
            presentedBannerWebDestination = BannerWebDestination(
                title: remoteBanner.item.title,
                url: url
            )
        }
        viewModel.send(.remoteBannerDismissed)
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

    struct BannerWebDestination: Identifiable {
        let title: String
        let url: URL

        var id: URL { url }
    }
}

#Preview("Onboarding not completed") {
    LaunchView()
}
