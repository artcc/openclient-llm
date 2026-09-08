//
//  SettingsView+FeedbackHelp.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 18/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

// MARK: - Support

extension SettingsView {
    func supportSection(_ loadedState: SettingsViewModel.LoadedState) -> some View {
        Section {
            if loadedState.isTipJarEnabled {
                Button {
                    isShowingTipJar = true
                } label: {
                    settingsDestinationLabel("Buy Me a Coffee", systemImage: "cup.and.saucer")
                }
                .buttonStyle(.plain)
            }

            Button {
                requestAppReview()
            } label: {
                settingsDestinationLabel("Rate the App", systemImage: "star", isExternal: true)
            }
            .buttonStyle(.plain)

            Button {
                isShowingVotice = true
            } label: {
                settingsDestinationLabel("Suggest Features", systemImage: "lightbulb")
            }
            .buttonStyle(.plain)

            Button {
                isShowingHelp = true
            } label: {
                settingsDestinationLabel("Help", systemImage: "questionmark.circle")
            }
            .buttonStyle(.plain)
        } header: {
            Text(String(localized: "Support"))
        }
    }
}
