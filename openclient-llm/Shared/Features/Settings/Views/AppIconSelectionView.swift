//
//  AppIconSelectionView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 26/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

#if os(iOS)
import SwiftUI

struct AppIconSelectionView: View {
    // MARK: - Properties

    let selectedIcon: AppIcon
    let canChangeIcon: Bool
    let isChangingIcon: Bool
    let errorMessage: String?
    let categories: [AppIcon.Category]
    let onSelect: (AppIcon) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.adaptive(minimum: 88, maximum: 112), spacing: 16)
    ]

    // MARK: - View

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    selectedIconHeader
                    statusView
                    iconCatalog
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .navigationTitle(String(localized: "App Icon"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Private

private extension AppIconSelectionView {
    var selectedIconHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                appIconImage(selectedIcon, size: 112, cornerRadius: 25)
                if isChangingIcon {
                    RoundedRectangle(cornerRadius: 25, style: .continuous)
                        .fill(.black.opacity(0.35))
                        .frame(width: 112, height: 112)
                    ProgressView()
                        .accessibilityLabel(String(localized: "Changing app icon..."))
                        .tint(.white)
                }
            }
            Text(String(localized: "Current Icon"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(selectedIcon.localizedName)
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    var statusView: some View {
        if !canChangeIcon {
            Label(
                String(localized: "App icon changes are unavailable on this device."),
                systemImage: "exclamationmark.triangle"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        } else if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.red)
        }
    }

    var iconCatalog: some View {
        ForEach(categories) { category in
            VStack(alignment: .leading, spacing: 14) {
                Text(category.localizedName)
                    .font(.headline)

                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(AppIcon.icons(in: category)) { icon in
                        iconButton(icon)
                    }
                }
            }
        }
    }

    func iconButton(_ icon: AppIcon) -> some View {
        let isSelected = icon == selectedIcon

        return Button {
            onSelect(icon)
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    appIconImage(icon, size: 76, cornerRadius: 17)
                        .overlay {
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                        }

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .background(.white, in: Circle())
                            .offset(x: 5, y: -5)
                    }
                }

                Text(icon.localizedName)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!canChangeIcon || isChangingIcon || isSelected)
        .accessibilityValue(isSelected ? String(localized: "Selected") : "")
    }

    func appIconImage(_ icon: AppIcon, size: CGFloat, cornerRadius: CGFloat) -> some View {
        AppIconPreviewImage(icon: icon)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
    }
}

#Preview {
    AppIconSelectionView(
        selectedIcon: .ocean,
        canChangeIcon: true,
        isChangingIcon: false,
        errorMessage: nil,
        categories: AppIcon.Category.allCases,
        onSelect: { _ in }
    )
}
#endif
