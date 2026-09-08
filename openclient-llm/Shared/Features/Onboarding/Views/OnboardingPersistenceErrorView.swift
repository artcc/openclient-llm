//
//  OnboardingPersistenceErrorView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 14/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct OnboardingPersistenceErrorView: View {
    let message: String
    let attempt: Int

    @AccessibilityFocusState private var isFocused: Bool

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline)
            .foregroundStyle(.red)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityFocused($isFocused)
            .task(id: attempt) {
                guard attempt > 0 else { return }
                isFocused = false
                await Task.yield()
                isFocused = true
            }
    }
}

#Preview {
    OnboardingPersistenceErrorView(message: "The server configuration could not be saved.", attempt: 1)
        .padding()
}
