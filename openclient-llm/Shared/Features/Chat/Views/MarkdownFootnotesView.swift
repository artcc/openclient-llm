//
//  MarkdownFootnotesView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 13/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct MarkdownFootnotesView: View {
    let footnotes: [MarkdownFootnote]
    let inlineContent: [String: AttributedString]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            ForEach(footnotes, id: \.number) { footnote in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: "\(footnote.number).")
                        .monospacedDigit()
                    MarkdownInlineText(inlineContent[footnote.content] ?? AttributedString(footnote.content))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
    }
}

#Preview {
    MarkdownFootnotesView(
        footnotes: [
            MarkdownFootnote(number: 1, label: "source", content: "Source and additional context."),
            MarkdownFootnote(number: 2, label: "details", content: "A longer note.\nWith a second line.")
        ],
        inlineContent: [:]
    )
    .padding()
}
