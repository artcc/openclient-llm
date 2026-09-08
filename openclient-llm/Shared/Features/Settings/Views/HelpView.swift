//
//  HelpView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 18/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct HelpView: View {
    // MARK: - Properties

    @State private var didResetTips = false
    @Environment(\.dismiss) private var dismiss

    // MARK: - View

    var body: some View {
        NavigationStack {
            helpContent
                .navigationTitle(String(localized: "Help"))
#if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
#endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Done")) { dismiss() }
                    }
                }
        }
    }
}

// MARK: - Private

private extension HelpView {
    var helpContent: some View {
        List {
            shareExtensionSection
            urlSchemeSection
            shortcutsSection
            featureTipsSection
        }
#if os(macOS)
        .listStyle(.inset)
#endif
        .alert(String(localized: "Feature Tips Reset"), isPresented: $didResetTips) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(String(localized: "Feature tips can appear again when their conditions are met."))
        }
    }

    // MARK: - Share Extension

    var shareExtensionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(
                    localized: "Share text, links, images, or PDFs from any app into OpenClient."
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    HelpStep(number: 1, text: String(localized: "Tap the Share button in any app."))
                    HelpStep(number: 2, text: String(localized: "Scroll the share sheet and tap **OpenClient**."))
                    HelpStep(
                        number: 3,
                        text: String(localized: "The app opens with a new conversation pre-filled with your content.")
                    )
                }
                .padding(.top, 4)
            }
            .padding(.vertical, 4)
        } header: {
            Label(String(localized: "Share Extension"), systemImage: "square.and.arrow.up")
        }
    }

    // MARK: - URL Scheme

    var urlSchemeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(
                    localized: "Open the app from Shortcuts, other apps, or a browser using `openclient://`."
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)

                urlSchemeExample(
                    title: String(localized: "New chat with text"),
                    url: "openclient://chat?text=Hello"
                )

                urlSchemeExample(
                    title: String(localized: "New chat with a URL"),
                    url: "openclient://chat?url=https://example.com"
                )

                urlSchemeExample(
                    title: String(localized: "Open a conversation by ID"),
                    url: "openclient://conversation?id=<UUID>"
                )
            }
            .padding(.vertical, 4)
        } header: {
            Label(String(localized: "URL Scheme"), systemImage: "link")
        }
    }

    func urlSchemeExample(title: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            HStack(spacing: 8) {
                Text(url)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Spacer()
                Button {
                    copyToClipboard(url)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Copy URL"))
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    // MARK: - Apple Shortcuts

    var shortcutsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(
                    localized: "Automate OpenClient with the Shortcuts app using the URL scheme actions above."
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    HelpStep(number: 1, text: String(localized: "Open **Shortcuts** and create a new shortcut."))
                    HelpStep(number: 2, text: String(localized: "Add an **Open URLs** action."))
                    HelpStep(
                        number: 3,
                        text: String(localized: "Enter a URL such as `openclient://chat?text=Summarise this`.")
                    )
                }
                .padding(.top, 4)
            }
            .padding(.vertical, 4)
        } header: {
            Label(String(localized: "Apple Shortcuts"), systemImage: "arrow.trianglehead.branch")
        }
    }

    // MARK: - Feature Tips

    var featureTipsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Tips appear only when their related features are available."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button(String(localized: "Show Feature Tips Again")) {
                    Task {
                        await AppTips.resetEligibility()
                        didResetTips = true
                    }
                }
#if os(macOS)
                .buttonStyle(.bordered)
#endif
            }
            .padding(.vertical, 4)
        } header: {
            Label(String(localized: "Feature Tips"), systemImage: "lightbulb.max")
        }
    }

    // MARK: - Helpers

    func copyToClipboard(_ text: String) {
#if os(iOS)
        UIPasteboard.general.string = text
#elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
#endif
    }
}

// MARK: - HelpStep

private struct HelpStep: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(.tint, in: Circle())

            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    init(number: Int, text: String) {
        self.number = number
        self.text = LocalizedStringKey(text)
    }
}

#Preview {
    HelpView()
}
