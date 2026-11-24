//
//  WhatsNewView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 24/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct WhatsNewView: View {
    let news: RemoteWhatsNew
    let onContinue: () -> Void
    let onAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: "OpenClient \(news.version)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(verbatim: news.item.title)
                            .font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                    }

                    ForEach(news.item.highlights.indices, id: \.self) { index in
                        WhatsNewHighlightRow(highlight: news.item.highlights[index])
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }

            Divider()
            footer
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .layoutPriority(1)
        }
#if os(macOS)
        .frame(minWidth: 360, idealWidth: 460, minHeight: 300, idealHeight: 480)
#else
        .presentationSizing(.form)
        .presentationDragIndicator(.visible)
#endif
    }
}

private extension WhatsNewView {
    @ViewBuilder
    var footer: some View {
        if let actionTitle = news.actionTitle {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { buttons(actionTitle: actionTitle) }
                VStack(spacing: 8) { buttons(actionTitle: actionTitle) }
            }
        } else {
            continueButton.buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    func buttons(actionTitle: String) -> some View {
        Button(action: onAction) {
            buttonLabel(Text(verbatim: actionTitle))
        }
        .buttonStyle(.borderedProminent)

        continueButton.buttonStyle(.borderless)
    }

    var continueButton: some View {
        Button(action: onContinue) {
            buttonLabel(Text("Continue"))
        }
        .keyboardShortcut(.defaultAction)
    }

    func buttonLabel(_ text: Text) -> some View {
        text
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
#if os(iOS)
            .frame(minHeight: 44)
#endif
            .contentShape(.rect)
    }
}

private struct WhatsNewHighlightRow: View {
    @ScaledMetric(relativeTo: .title2) private var symbolWidth = 32.0

    let highlight: RemoteWhatsNew.Highlight

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: highlight.symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: symbolWidth)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: highlight.title)
                    .font(.headline)
                Text(verbatim: highlight.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
private func previewSheet(actionTitle: String?) -> some View {
    WhatsNewView(
        news: RemoteWhatsNew(
            id: "preview",
            version: "2.0",
            item: .init(
                title: "What’s new in OpenClient",
                highlights: [
                    .init(symbol: "pin", title: "Pinned chats", body: "Keep your most-used conversations at the top."),
                    .init(symbol: "tag", title: "Tags", body: "Organise your conversations by topic.")
                ],
                actionTitle: actionTitle
            ),
            action: actionTitle == nil ? nil : .feedback,
            url: nil
        ),
        onContinue: {},
        onAction: {}
    )
}

#Preview("Compact with action") {
    previewSheet(actionTitle: "Share feedback about this release")
        .environment(\.dynamicTypeSize, .accessibility1)
        .frame(width: 360, height: 460)
}

#Preview("Wide without action") {
    previewSheet(actionTitle: nil)
        .frame(width: 520, height: 460)
}
#endif
