//
//  OnboardingWelcomeView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 07/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct OnboardingWelcomeView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            OnboardingConnectionIllustration()
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                Text("Your AI, Your Way")
                    .font(.poppins(.semiBold, size: 34, relativeTo: .largeTitle))
                    .accessibilityAddTraits(.isHeader)
                Text(
                    "Bring your server. Connect to LiteLLM, Ollama, LM Studio, or any OpenAI-compatible server."
                )
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 20) {
                benefit(
                    "Your choice of models",
                    description: "Use the models available on your server, all in one conversation app.",
                    icon: "square.stack.3d.up"
                )
                benefit(
                    "Your server, your control",
                    description: "Connect directly to the server you choose. No app telemetry.",
                    icon: "lock.shield"
                )
                benefit(
                    "Open by design",
                    description: "Open source on GitHub. Explore the code or contribute.",
                    icon: "chevron.left.forwardslash.chevron.right"
                )
            }
        }
    }

    private func benefit(_ title: LocalizedStringKey, description: LocalizedStringKey, icon: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.appAccent)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ScrollView {
        OnboardingWelcomeView()
            .padding(24)
    }
}

#Preview("Welcome, dark") {
    ScrollView {
        OnboardingWelcomeView()
            .padding(24)
    }
    .environment(\.colorScheme, .dark)
}
