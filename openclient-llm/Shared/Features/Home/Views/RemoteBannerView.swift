//
//  RemoteBannerView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 09/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct RemoteBannerView: View {
    // MARK: - Properties

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let banner: RemoteBanner
    let onDismiss: () -> Void
    let onAction: () -> Void

    // MARK: - View

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        emoji
                        Spacer()
                        closeButton
                    }
                    stackedContent
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    emoji
                    adaptiveContent
                    closeButton
                }
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Private

private extension RemoteBannerView {
    @ViewBuilder
    var adaptiveContent: some View {
        if banner.item.cta.isEmpty {
            message
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    message
                    actionButton
                }
                stackedContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var stackedContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            message
            if !banner.item.cta.isEmpty {
                actionButton
            }
        }
    }

    @ViewBuilder
    var emoji: some View {
        if !banner.item.emoji.isEmpty {
            Text(verbatim: banner.item.emoji)
                .font(.title2)
                .padding(7)
                .background(.quaternary, in: .rect(cornerRadius: 12))
                .accessibilityHidden(true)
        }
    }

    var message: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(banner.item.title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(banner.item.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    var actionButton: some View {
        Button(action: onAction) {
            Text(verbatim: banner.item.cta)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
#if os(iOS)
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
#endif
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    var closeButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.caption.weight(.semibold))
#if os(iOS)
                .frame(width: 44, height: 44)
#else
                .frame(width: 30, height: 30)
#endif
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Dismiss banner"))
        .accessibilitySortPriority(-1)
    }
}

#if DEBUG
#Preview("Compact") {
    RemoteBannerView.previewBanner
        .frame(width: 360)
}

#Preview("Wide") {
    RemoteBannerView.previewBanner
        .frame(width: 720)
}

#Preview("Large text") {
    RemoteBannerView.previewBanner
        .environment(\.dynamicTypeSize, .accessibility2)
        .frame(width: 360)
}

private extension RemoteBannerView {
    static var previewBanner: some View {
        RemoteBannerView(
            banner: RemoteBanner(
                id: "preview",
                item: .init(
                    title: "OpenClient news",
                    subtitle: "Important news, tips, and updates will appear here.",
                    cta: "Learn more",
                    action: .openURL,
                    url: "https://example.com",
                    emoji: "✨"
                )
            ),
            onDismiss: {},
            onAction: {}
        )
        .padding()
    }
}
#endif
