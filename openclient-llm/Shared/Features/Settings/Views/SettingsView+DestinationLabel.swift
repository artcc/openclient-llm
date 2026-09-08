//
//  SettingsView+DestinationLabel.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 08/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

extension SettingsView {
    @ViewBuilder
    func settingsDestinationLabel(
        _ title: LocalizedStringKey,
        systemImage: String,
        isExternal: Bool = false
    ) -> some View {
#if os(macOS)
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Image(systemName: isExternal ? "arrow.up.right.square" : "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
#else
        Label(title, systemImage: systemImage)
#endif
    }
}
