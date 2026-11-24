//
//  WhatsNewView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 24/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct WhatsNewView: View {
    fileprivate static let cardShape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    let news: RemoteWhatsNew
    let onContinue: () -> Void
    let onAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .vertical) {
                notes.fixedSize(horizontal: false, vertical: true)
                ScrollView { notes }
                    .scrollBounceBehavior(.basedOnSize)
            }
            footer
                .layoutPriority(1)
        }
        .padding(20)
        .frame(maxWidth: 400, alignment: .leading)
        .background(.background, in: Self.cardShape)
        .overlay { Self.cardShape.strokeBorder(.primary.opacity(0.12), lineWidth: 1).allowsHitTesting(false) }
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
        .anchorPreference(key: WhatsNewCardBounds.self, value: .bounds) { $0 }
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape, onContinue)
    }
}

private extension WhatsNewView {
    var notes: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                CurrentAppIconImage()
                    .frame(width: 26, height: 26)
                    .clipShape(.rect(cornerRadius: 6))
                    .accessibilityHidden(true)
                Text("What's New")
                    .textCase(.uppercase)
                    .fontWeight(.semibold)
                Text(verbatim: "· \(news.version)")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)

            Text(verbatim: news.item.title)
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)

            ForEach(news.item.highlights.indices, id: \.self) { index in
                WhatsNewHighlightRow(highlight: news.item.highlights[index])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var footer: some View {
        if let actionTitle = news.actionTitle {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    contextualAction(actionTitle)
                    Spacer(minLength: 0)
                    continueButton
                }
                VStack(alignment: .trailing, spacing: 4) {
                    contextualAction(actionTitle)
                    continueButton
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } else {
            continueButton.frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    func contextualAction(_ title: String) -> some View {
        Button(action: onAction) {
            HStack(spacing: 4) {
                Text(verbatim: title)
                if news.action == .writeReview {
                    Image(systemName: "arrow.up.right")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
            }
            .font(.subheadline.weight(.medium))
            .multilineTextAlignment(.leading)
#if os(iOS)
            .frame(minHeight: 44)
#endif
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
    }

    var continueButton: some View {
        Button(action: onContinue) {
            Text("Continue")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 6)
#if os(iOS)
                .frame(minHeight: 32)
#endif
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
    }
}

private nonisolated struct WhatsNewCardBounds: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

struct WhatsNewBackdrop: ViewModifier {
    func body(content: Content) -> some View {
        content.overlayPreferenceValue(WhatsNewCardBounds.self) { anchor in
            if let anchor {
                GeometryReader { geometry in
                    Path { path in
                        path.addRect(CGRect(origin: .zero, size: geometry.size))
                        path.addPath(WhatsNewView.cardShape.path(in: geometry[anchor]))
                    }
                    .fill(.black.opacity(0.3), style: FillStyle(eoFill: true))
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

private struct WhatsNewHighlightRow: View {
    @ScaledMetric(relativeTo: .subheadline) private var symbolWidth = 24.0

    let highlight: RemoteWhatsNew.Highlight

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: highlight.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: symbolWidth)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: highlight.title)
                    .font(.subheadline.weight(.semibold))
                Text(verbatim: highlight.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
private func previewCard(actionTitle: String?) -> some View {
    WhatsNewView(
        news: RemoteWhatsNew(
            id: "preview",
            version: "1.0.0",
            item: .init(
                title: "Un sitio para los chats de un mismo tema",
                highlights: [
                    .init(symbol: "folder", title: "Organiza tus chats en carpetas",
                          body: "Mueve un chat o varios a la vez. Su orden en el historial no cambia."),
                    .init(symbol: "arrow.branch", title: "Mantén juntas las ramificaciones",
                          body: "Cuando creas una rama de un chat, la nueva conversación empieza en la misma carpeta.")
                ],
                actionTitle: actionTitle
            ),
            action: actionTitle == nil ? nil : .writeReview,
            url: nil
        ),
        onContinue: {},
        onAction: {}
    )
}

#Preview("iPhone · Folder release") {
    previewCard(actionTitle: "Escribir una reseña")
        .padding(12)
        .frame(width: 375, height: 580, alignment: .bottomTrailing)
        .modifier(WhatsNewBackdrop())
        .environment(\.locale, Locale(identifier: "es"))
}

#Preview("Large text · No action") {
    previewCard(actionTitle: nil)
        .environment(\.dynamicTypeSize, .accessibility2)
        .padding(16)
        .frame(width: 520, height: 420, alignment: .bottomTrailing)
        .modifier(WhatsNewBackdrop())
}
#endif
