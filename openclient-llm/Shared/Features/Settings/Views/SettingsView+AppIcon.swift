//
//  SettingsView+AppIcon.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 26/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI
#if os(iOS)
import TipKit
#endif

extension SettingsView {
    @ViewBuilder
    func appIconSection(_ loadedState: SettingsViewModel.LoadedState) -> some View {
#if os(iOS)
        AppIconSettingsSection(
            loadedState: loadedState,
            onSelect: { viewModel.send(.appIconSelected($0)) }
        )
#else
        EmptyView()
#endif
    }
}

#if os(iOS)
private struct AppIconSettingsSection: View {
    let loadedState: SettingsViewModel.LoadedState
    let onSelect: (AppIcon) -> Void

    @State private var isShowingSelection = false

    var body: some View {
        Section {
            Button {
                AppTips.appIconSelection.invalidate(reason: .actionPerformed)
                isShowingSelection = true
            } label: {
                HStack(spacing: 12) {
                    AppIconPreviewImage(icon: loadedState.selectedAppIcon)
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "App Icon"))
                        Text(loadedState.selectedAppIcon.localizedName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .popoverTip(loadedState.canChangeAppIcon ? AppTips.appIconSelection : nil)
            .sheet(isPresented: $isShowingSelection) {
                AppIconSelectionView(
                    selectedIcon: loadedState.selectedAppIcon,
                    canChangeIcon: loadedState.canChangeAppIcon,
                    isChangingIcon: loadedState.isChangingAppIcon,
                    errorMessage: loadedState.appIconError,
                    categories: loadedState.visibleAppIconCategories,
                    onSelect: onSelect
                )
            }
        } header: {
            Text(String(localized: "Appearance"))
        } footer: {
            Text(String(localized: "Choose how OpenClient appears on your Home Screen."))
        }
    }
}
#endif
