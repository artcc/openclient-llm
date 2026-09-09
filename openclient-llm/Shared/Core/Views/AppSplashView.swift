//
//  AppSplashView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 14/07/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct AppSplashView: View {
    // MARK: - Properties

    let showsLoadingIndicator: Bool
    let backgroundMaterial: Material

    // MARK: - Init

    init(showsLoadingIndicator: Bool = false, backgroundMaterial: Material = .ultraThinMaterial) {
        self.showsLoadingIndicator = showsLoadingIndicator
        self.backgroundMaterial = backgroundMaterial
    }

    // MARK: - View

    var body: some View {
        ZStack {
            Rectangle()
                .fill(backgroundMaterial)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                CurrentAppIconImage()
                    .scaledToFit()
                    .frame(width: 125, height: 125)
                    .shadow(color: .cyan.opacity(0.4), radius: 24, x: 0, y: 8)
                    .cornerRadius(25)
                    .accessibilityHidden(true)

                VStack(spacing: 5) {
                    Text(String(localized: "OpenClient"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(String(localized: "Your AI conversations"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if showsLoadingIndicator {
                    ProgressView()
                        .accessibilityLabel(String(localized: "Loading"))
                        .tint(.secondary)
                        .controlSize(.small)
                        .padding(.top, 5)
                }
            }
        }
        .transition(.opacity)
    }
}

#Preview {
    AppSplashView(showsLoadingIndicator: true)
}
