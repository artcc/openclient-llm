//
//  OnboardingView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct OnboardingView: View {
    // MARK: - Properties

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel = OnboardingViewModel()
    @State private var serverURL: String = ""
    @State private var apiKey: String = ""
    @State private var isAPIKeyVisible = false

    let onComplete: () -> Void

    // MARK: - View

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView()
                    .tint(.secondary)
            case .loaded(let loadedState):
                loadedView(loadedState)
            }
        }
        .task {
            viewModel.onComplete = onComplete
            viewModel.send(.viewAppeared)
            if case .loaded(let initialState) = viewModel.state {
                serverURL = initialState.serverURL
                apiKey = initialState.apiKey
            }
        }
    }
}

// MARK: - Private

private extension OnboardingView {
    var backgroundColor: Color {
#if os(macOS)
        Color(nsColor: .windowBackgroundColor)
#else
        Color(uiColor: .systemBackground)
#endif
    }

    func loadedView(_ loadedState: OnboardingViewModel.LoadedState) -> some View {
        GlassEffectContainer(spacing: 24) {
#if os(macOS)
            macOSLayout(loadedState)
#else
            VStack(spacing: 0) {
                topBar(loadedState)
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 20)

                ScrollView {
                    stepContent(loadedState)
                        .frame(maxWidth: 520, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                .scrollBounceBehavior(.basedOnSize)
#if os(iOS)
                .scrollDismissesKeyboard(.interactively)
#endif
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    bottomAction(loadedState)
                        .frame(maxWidth: 520, alignment: .trailing)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 12)
                        .frame(maxWidth: .infinity)
                        .background(backgroundColor)
                }
            }
#endif
        }
        .background(backgroundColor.ignoresSafeArea())
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: loadedState.currentStep)
        .tint(Color.appAccent)
    }

#if os(macOS)
    func macOSLayout(_ loadedState: OnboardingViewModel.LoadedState) -> some View {
        VStack(spacing: 0) {
            topBar(loadedState)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                stepContent(loadedState)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 16) {
                Divider()
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        skippingNotice(loadedState)
                            .fixedSize()
                        Spacer(minLength: 0)
                        primaryAction(loadedState)
                            .fixedSize()
                    }
                    bottomAction(loadedState)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 568, maxHeight: 660)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
#endif

    func topBar(_ loadedState: OnboardingViewModel.LoadedState) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                if loadedState.currentStep != .welcome {
                    Button {
                        viewModel.send(.backTapped)
                    } label: {
                        Label("Back", systemImage: "chevron.left")
#if os(iOS)
                            .frame(minHeight: 44)
#endif
                    }
#if os(macOS)
                    .buttonStyle(.bordered)
#else
                    .buttonStyle(.glass)
#endif
                } else {
                    Text("OpenClient")
                        .font(.headline)
                }

                Spacer(minLength: 16)

                Button {
                    viewModel.send(.skipTapped)
                } label: {
                    Text("Skip")
#if os(iOS)
                        .frame(minWidth: 44, minHeight: 44)
#endif
                }
#if os(macOS)
                .buttonStyle(.bordered)
#else
                .buttonStyle(.glass)
#endif
                .accessibilityHint("Finish onboarding without saving these server settings.")
            }

            stepIndicator(currentStep: loadedState.currentStep)
        }
    }

    func stepIndicator(currentStep: OnboardingStep) -> some View {
        let number = (OnboardingStep.allCases.firstIndex(of: currentStep) ?? 0) + 1
        return VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(stepName(currentStep))
                    Spacer(minLength: 12)
                    Text("\(number) of 3")
                        .monospacedDigit()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(stepName(currentStep))
                    Text("\(number) of 3")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(Array(OnboardingStep.allCases.enumerated()), id: \.offset) { index, _ in
                    Capsule()
                        .fill(index < number ? Color.appAccent : Color.secondary.opacity(0.2))
                        .frame(height: 3)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(stepName(currentStep)))
        .accessibilityValue(Text("Step \(number) of 3"))
    }

    func stepName(_ step: OnboardingStep) -> String {
        switch step {
        case .welcome: String(localized: "Welcome")
        case .serverConfiguration: String(localized: "Server configuration")
        case .allSet: String(localized: "Finish setup")
        }
    }

    @ViewBuilder
    func stepContent(_ loadedState: OnboardingViewModel.LoadedState) -> some View {
        switch loadedState.currentStep {
        case .welcome:
            OnboardingWelcomeView()
        case .serverConfiguration:
            OnboardingServerConfigurationView(
                serverURL: $serverURL,
                apiKey: $apiKey,
                isAPIKeyVisible: $isAPIKeyVisible,
                state: loadedState,
                onEvent: viewModel.send
            )
        case .allSet:
            allSetStep(loadedState)
        }
    }

    func allSetStep(_ loadedState: OnboardingViewModel.LoadedState) -> some View {
        let persistenceError: String?
        if case .failure(let message) = loadedState.connectionStatus {
            persistenceError = message
        } else {
            persistenceError = nil
        }
        return VStack(alignment: .leading, spacing: 24) {
            OnboardingCompletionStatusView(hasPersistenceError: persistenceError != nil)

            if !loadedState.serverURL.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Server URL", systemImage: "server.rack")
                        .font(.subheadline.weight(.medium))
                    Text(loadedState.serverURL)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.background.secondary, in: .rect(cornerRadius: 16))
            }

            if let persistenceError {
                OnboardingPersistenceErrorView(
                    message: persistenceError,
                    attempt: loadedState.persistenceFailureCount
                )
            }
        }
    }

    func bottomAction(_ loadedState: OnboardingViewModel.LoadedState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            skippingNotice(loadedState)

            primaryAction(loadedState)
        }
    }

    @ViewBuilder
    func skippingNotice(_ loadedState: OnboardingViewModel.LoadedState) -> some View {
        if loadedState.currentStep != .welcome {
            Text("Skipping won't save these server settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    func primaryAction(_ loadedState: OnboardingViewModel.LoadedState) -> some View {
        Button {
            switch loadedState.currentStep {
            case .welcome: viewModel.send(.getStartedTapped)
            case .serverConfiguration: viewModel.send(.nextTapped)
            case .allSet: viewModel.send(.startChattingTapped)
            }
        } label: {
            Text(actionTitle(loadedState))
                .font(.headline)
                .multilineTextAlignment(.center)
#if os(iOS)
                .frame(maxWidth: .infinity, minHeight: 44)
#endif
        }
#if os(macOS)
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: .infinity, alignment: .trailing)
#else
        .buttonStyle(.glassProminent)
#endif
        .controlSize(.large)
        .disabled(loadedState.currentStep == .serverConfiguration && loadedState.connectionStatus != .success)
    }

    func actionTitle(_ loadedState: OnboardingViewModel.LoadedState) -> String {
        switch loadedState.currentStep {
        case .welcome:
            String(localized: "Set Up Your Server")
        case .serverConfiguration:
            String(localized: "Continue")
        case .allSet:
            if case .failure = loadedState.connectionStatus {
                String(localized: "Try Again")
            } else {
                String(localized: "Finish Setup")
            }
        }
    }
}

#if os(macOS)
#Preview("Onboarding, minimum window") {
    OnboardingView {}
        .frame(width: 800, height: 600)
}

#Preview("Onboarding, large window") {
    OnboardingView {}
        .frame(width: 1100, height: 800)
}
#else
#Preview {
    OnboardingView {}
}
#endif
