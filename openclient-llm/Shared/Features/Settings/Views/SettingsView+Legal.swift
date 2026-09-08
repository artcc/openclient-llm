//
//  SettingsView+Legal.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 09/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

extension SettingsView {
    func legalSection() -> some View {
        Section {
            Button {
                presentedWebURL = .privacyPolicy
            } label: {
                settingsDestinationLabel("Privacy Policy", systemImage: "hand.raised")
            }
            .buttonStyle(.plain)

            Button {
                presentedWebURL = .termsOfUse
            } label: {
                settingsDestinationLabel("Terms of Use", systemImage: "doc.text")
            }
            .buttonStyle(.plain)

            Button {
                presentedWebURL = .authorGitHub
            } label: {
#if os(macOS)
                settingsDestinationLabel("Author", systemImage: "person.circle")
#else
                HStack {
                    Label(String(localized: "Author"), systemImage: "person.circle")
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
#endif
            }
            .buttonStyle(.plain)

            HStack {
                Text(String(localized: "Version \(appVersion) (\(appBuild))"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 5)
                Spacer()
            }
        } header: {
            Text(String(localized: "About"))
        }
    }
}
