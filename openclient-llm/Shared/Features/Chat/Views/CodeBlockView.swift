//
//  CodeBlockView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 31/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI
#if canImport(UIKit)
import SwiftUI
#elseif canImport(AppKit)
import AppKit
#endif

struct CodeBlockView: View {
    // MARK: - Properties

    let code: String
    let language: String?

    @State private var copied = false

    // MARK: - View

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
                .overlay(Color.primary.opacity(0.1))
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color.primary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Private

private extension CodeBlockView {
    var header: some View {
        HStack(spacing: 12) {
            Text(language ?? String(localized: "Code"))
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                copyCode()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                    Text(copied ? String(localized: "Copied") : String(localized: "Copy"))
                        .font(.caption)
                }
                .foregroundStyle(copied ? Color.green : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
            }
#if os(macOS)
            .buttonStyle(.bordered)
            .controlSize(.small)
#else
            .buttonStyle(.plain)
#endif
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Color.primary.opacity(0.03),
            in: UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12)
        )
    }

    func copyCode() {
#if os(iOS)
        UIPasteboard.general.string = code
#elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
#endif
        withAnimation(.easeInOut(duration: 0.15)) {
            copied = true
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeInOut(duration: 0.15)) {
                copied = false
            }
        }
    }
}

#Preview {
    CodeBlockView(
        code: "func hello() -> String {\n    return \"Hello, world!\"\n}",
        language: "swift"
    )
    .padding()
}

#Preview("Long Lines and No Language") {
    VStack(alignment: .leading, spacing: 16) {
        CodeBlockView(
            code: "let description = \"A long line of code that remains accessible through horizontal scrolling.\"",
            language: "swift"
        )
        CodeBlockView(
            code: "First line\n    Indented content\n\nLast line",
            language: nil
        )
    }
    .padding()
    .frame(width: 340)
}
