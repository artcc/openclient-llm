//
//  OnboardingCompletionStatusView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 14/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct OnboardingCompletionStatusView: View {
    let hasPersistenceError: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingConnectionIllustration()
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                Label(hasPersistenceError
                    ? String(localized: "Not saved")
                    : String(localized: "Connection verified"),
                    systemImage: hasPersistenceError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(statusColor)

                Text(hasPersistenceError
                    ? String(localized: "Server Configuration Wasn't Saved")
                    : String(localized: "Connection ready"))
                    .font(.poppins(.semiBold, size: 30, relativeTo: .largeTitle))
                    .accessibilityAddTraits(.isHeader)
                Text(hasPersistenceError
                    ? String(localized: "Try again to save your server settings, or go back to review them.")
                    : String(localized: "Finish setup to save your server settings and start your first conversation."))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private extension OnboardingCompletionStatusView {
    var statusColor: Color { hasPersistenceError ? .red : .green }
}

#Preview {
    OnboardingCompletionStatusView(hasPersistenceError: true)
        .padding()
}

#Preview("Connection ready") {
    OnboardingCompletionStatusView(hasPersistenceError: false)
        .padding()
}
