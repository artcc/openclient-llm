//
//  TipJarView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 25/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import ConfettiSwiftUI
import SwiftUI

struct TipJarView: View {
    // MARK: - Properties

    private enum SupportSection: Hashable {
        case subscriptions
        case oneTime
    }

    enum LegalPage: Hashable, Identifiable {
        case termsOfUse
        case privacyPolicy

        var id: Self { self }

        var title: String {
            switch self {
            case .termsOfUse:
                String(localized: "Terms of Use")
            case .privacyPolicy:
                String(localized: "Privacy Policy")
            }
        }

        var url: URL? {
            switch self {
            case .termsOfUse:
                Constants.URLs.termsOfUse
            case .privacyPolicy:
                Constants.URLs.privacyPolicy
            }
        }
    }

    struct HeaderMetrics {
        let logoSize: CGFloat
        let spacing: CGFloat
        let textSpacing: CGFloat
        let topPadding: CGFloat
        let shadowRadius: CGFloat
        let shadowOffset: CGFloat
    }

    @State private var viewModel = TipJarViewModel()
    @State private var confettiTrigger: Int = 0
    @State private var selectedSupportSection: SupportSection = .subscriptions
    @State private var presentedLegalPage: LegalPage?

    @Environment(\.dismiss) private var dismiss

    // MARK: - View

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .loading:
                    ProgressView()
                        .accessibilityLabel(String(localized: "Loading support options..."))
                        .tint(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .loaded(let loadedState):
                    loadedView(loadedState)
                case .error(let message):
                    errorView(message)
                }
            }
            .navigationTitle(String(localized: "Support OpenClient"))
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Close")) {
                        dismiss()
                    }
                }
            }
        }
        .task {
            viewModel.send(.viewAppeared)
        }
        .confettiCannon(
            trigger: $confettiTrigger,
            confettis: [.text("☕"), .shape(.circle), .shape(.triangle), .shape(.square)],
            colors: [.brown, .orange, .yellow, .pink, .purple],
            repetitions: 2,
            repetitionInterval: 0.5
        )
        .onChange(of: showThankYou) { _, isShowing in
            if isShowing {
                confettiTrigger += 1
            }
        }
        .sheet(item: $presentedLegalPage) { page in
            if let url = page.url {
                WebContentView(title: page.title, url: url)
            }
        }
    }
}

// MARK: - Private

private extension TipJarView {
    var showThankYou: Bool {
        guard case .loaded(let loadedState) = viewModel.state else { return false }
        return loadedState.showThankYou
    }

    func loadedView(_ loadedState: TipJarViewModel.LoadedState) -> some View {
        let isProcessing = loadedState.isPurchasing || loadedState.isRestoring
        return ScrollView {
            VStack(spacing: 25) {
                Spacer()
                headerSection()
                supportSectionPicker()
                switch selectedSupportSection {
                case .subscriptions:
                    subscriptionsSection(loadedState)
                    subscriptionLinks(loadedState)
                case .oneTime:
                    tipsSection(loadedState)
                }
                Spacer()
            }
            .padding()
        }
        .overlay {
            if isProcessing {
                purchasingOverlay()
            }
        }
        .alert(
            String(localized: "Thank you! ☕"),
            isPresented: thankYouBinding(loadedState)
        ) {
            Button(String(localized: "You're welcome!"), role: .cancel) {
                viewModel.send(.thankYouDismissed)
                dismiss()
            }
        } message: {
            Text(String(localized: "Your support means a lot and helps keep the app free and open source."))
        }
        .alert(
            String(localized: "Purchases restored"),
            isPresented: restoreConfirmationBinding(loadedState)
        ) {
            Button(String(localized: "OK"), role: .cancel) {
                viewModel.send(.restoreConfirmationDismissed)
                dismiss()
            }
        } message: {
            Text(String(localized: "Your App Store purchases have been synchronized."))
        }
    }

    func headerSection() -> some View {
        VStack(spacing: headerMetrics.spacing) {
            CurrentAppIconImage()
                .scaledToFit()
                .frame(width: headerMetrics.logoSize, height: headerMetrics.logoSize)
                .cornerRadius(25)
                .shadow(
                    color: .cyan.opacity(0.4),
                    radius: headerMetrics.shadowRadius,
                    x: 0,
                    y: headerMetrics.shadowOffset
                )

            VStack(spacing: headerMetrics.textSpacing) {
                Text(String(localized: "OpenClient is free and open source"))
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Text(String(localized: "Your support keeps development and updates going!"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, headerMetrics.topPadding)
    }

    func supportSectionPicker() -> some View {
        Picker(String(localized: "Support type"), selection: $selectedSupportSection) {
            Text(String(localized: "Subscriptions"))
                .tag(SupportSection.subscriptions)
            Text(String(localized: "One-time support"))
                .tag(SupportSection.oneTime)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 420)
    }

    @ViewBuilder
    func subscriptionsSection(_ loadedState: TipJarViewModel.LoadedState) -> some View {
        let products = subscriptionProducts(from: loadedState.products)
        let isProcessing = loadedState.isPurchasing || loadedState.isRestoring
        if !products.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Ongoing support"))
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(String(localized: "Support ongoing development, maintenance, and new features."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 12) {
                        ForEach(products) { product in
                            subscriptionCard(product, isDisabled: isProcessing)
                        }
                    }
                }

                Text(String(localized: "Renews automatically until canceled. No features are locked."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func subscriptionCard(_ product: TipProduct, isDisabled: Bool) -> some View {
        let isAnnual = product.kind == .annualSubscription
        return Button {
            viewModel.send(.productTapped(id: product.id))
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                if isAnnual {
                    Text(String(localized: "More support"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(subscriptionHighlightColor, in: .capsule)
                }

                HStack(spacing: 14) {
                    Text(product.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(product.displayPrice)
                            .font(.headline)
                            .foregroundStyle(isAnnual ? subscriptionHighlightColor : Color.primary)
                        Text(billingPeriodText(for: product.kind))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isAnnual ? subscriptionHighlightColor : .clear, lineWidth: 2)
            }
            .shadow(color: isAnnual ? subscriptionHighlightColor.opacity(0.18) : .clear, radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    func tipsSection(_ loadedState: TipJarViewModel.LoadedState) -> some View {
        let products = oneTimeProducts(from: loadedState.products)
        let isProcessing = loadedState.isPurchasing || loadedState.isRestoring
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "One-time support"))
                    .font(.headline)

                Text(String(localized: "Buy me a coffee · One-time purchase · Doesn't unlock any features"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 12) {
                    if products.count >= 3 {
                        coffeeCard(products[2], emoji: "☕☕☕", isFeatured: true, isDisabled: isProcessing)
                        HStack(spacing: 12) {
                            coffeeCard(products[1], emoji: "☕☕", isFeatured: false, isDisabled: isProcessing)
                            coffeeCard(products[0], emoji: "☕", isFeatured: false, isDisabled: isProcessing)
                        }
                    } else {
                        ForEach(products) { product in
                            coffeeCard(product, emoji: "☕", isFeatured: false, isDisabled: isProcessing)
                        }
                    }
                }
            }
        }
    }

    func coffeeCard(_ product: TipProduct, emoji: String, isFeatured: Bool, isDisabled: Bool) -> some View {
        Button {
            viewModel.send(.productTapped(id: product.id))
        } label: {
            VStack(spacing: 8) {
                Text(emoji)
                    .font(.system(size: isFeatured ? 40 : 28))
                Text(product.displayName)
                    .font(isFeatured ? .subheadline : .caption)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                Text(product.displayPrice)
                    .font(isFeatured ? .title2 : .callout)
                    .fontWeight(.bold)
                    .foregroundStyle(.accent)
            }
            .padding(.vertical, isFeatured ? 24 : 16)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    @ViewBuilder
    func subscriptionLinks(_ loadedState: TipJarViewModel.LoadedState) -> some View {
        if !subscriptionProducts(from: loadedState.products).isEmpty {
            VStack(spacing: 10) {
                if let manageSubscriptions = Constants.URLs.manageSubscriptions {
                    Link(String(localized: "Manage Subscriptions"), destination: manageSubscriptions)
                }

                Button(String(localized: "Restore Purchases")) {
                    viewModel.send(.restorePurchasesTapped)
                }
                .disabled(loadedState.isPurchasing || loadedState.isRestoring)

                HStack(spacing: 16) {
                    if LegalPage.termsOfUse.url != nil {
                        legalButton(.termsOfUse)
                    }
                    if LegalPage.privacyPolicy.url != nil {
                        legalButton(.privacyPolicy)
                    }
                }
            }
#if os(macOS)
            .buttonStyle(.plain)
            .foregroundStyle(subscriptionHighlightColor)
#endif
            .font(.footnote)
        }
    }

    func legalButton(_ page: LegalPage) -> some View {
        Button {
            presentedLegalPage = page
        } label: {
            Text(page.title)
                .foregroundStyle(subscriptionHighlightColor)
        }
        .buttonStyle(.plain)
    }

    func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func purchasingOverlay() -> some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .tint(.secondary)
                    .controlSize(.large)
                Text(String(localized: "Processing..."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
        }
    }

    func oneTimeProducts(from products: [TipProduct]) -> [TipProduct] {
        products.filter { $0.kind == .oneTimeTip }
    }

    var headerMetrics: HeaderMetrics {
#if os(macOS)
        HeaderMetrics(
            logoSize: 96,
            spacing: 14,
            textSpacing: 10,
            topPadding: 4,
            shadowRadius: 16,
            shadowOffset: 6
        )
#else
        HeaderMetrics(
            logoSize: 125,
            spacing: 20,
            textSpacing: 15,
            topPadding: 8,
            shadowRadius: 24,
            shadowOffset: 8
        )
#endif
    }

    var subscriptionHighlightColor: Color {
#if os(macOS)
        Color("AccentColor")
#else
        Color.accentColor
#endif
    }

    func subscriptionProducts(from products: [TipProduct]) -> [TipProduct] {
        [.annualSubscription, .monthlySubscription].compactMap { kind in
            products.first { $0.kind == kind }
        }
    }

    func billingPeriodText(for kind: TipProduct.Kind) -> String {
        switch kind {
        case .monthlySubscription:
            String(localized: "per month")
        case .annualSubscription:
            String(localized: "per year")
        case .oneTimeTip:
            String(localized: "one time")
        }
    }

    func thankYouBinding(_ loadedState: TipJarViewModel.LoadedState) -> Binding<Bool> {
        Binding(
            get: { loadedState.showThankYou },
            set: { newValue in
                if !newValue {
                    viewModel.send(.thankYouDismissed)
                }
            }
        )
    }

    func restoreConfirmationBinding(_ loadedState: TipJarViewModel.LoadedState) -> Binding<Bool> {
        Binding(
            get: { loadedState.showRestoreConfirmation },
            set: { newValue in
                if !newValue {
                    viewModel.send(.restoreConfirmationDismissed)
                }
            }
        )
    }
}

// MARK: - Preview

#Preview {
    TipJarView()
}
