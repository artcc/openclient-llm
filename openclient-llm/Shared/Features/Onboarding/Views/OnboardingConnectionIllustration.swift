//
//  OnboardingConnectionIllustration.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 07/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct OnboardingConnectionIllustration: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)

            connector

            VStack(spacing: 6) {
                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .clipShape(.rect(cornerRadius: 16))
                Text("OpenClient")
                    .font(.caption2.weight(.medium))
            }

            connector

            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.appAccent.opacity(0.2))
                    .frame(width: 48, height: 22)
                    .frame(width: 68, alignment: .trailing)
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.appAccent)
                    VStack(alignment: .leading, spacing: 5) {
                        Capsule().frame(width: 48, height: 3)
                        Capsule().frame(width: 36, height: 3)
                        Capsule().frame(width: 42, height: 3)
                    }
                    .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 20)
        .dynamicTypeSize(...DynamicTypeSize.large)
        .accessibilityHidden(true)
    }

    private var connector: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.tertiary)
    }
}

#Preview {
    OnboardingConnectionIllustration()
        .padding()
}
