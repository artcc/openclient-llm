//
//  BlockquoteView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 29/07/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct BlockquoteView: View {
    // MARK: - Properties

    let content: String
    let inlineContent: [String: AttributedString]

    init(content: String, inlineContent: [String: AttributedString]) {
        self.content = content
        self.inlineContent = inlineContent
    }

    // MARK: - View

    var body: some View {
        Text(inlineContent[content] ?? AttributedString(content))
            .font(.callout)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 13)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.appAccent.opacity(0.5))
                    .frame(width: 3)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

#Preview {
    let simple = "This is a simple blockquote with a single line."
    let formatted = "This is a formatted blockquote with inline code."
    let multiline = "This is a longer blockquote that spans\n"
        + "multiple lines to demonstrate\n"
        + "how the view handles wrapping."

    VStack(spacing: 16) {
        BlockquoteView(content: simple, inlineContent: [:])
        BlockquoteView(content: formatted, inlineContent: [:])
        BlockquoteView(content: multiline, inlineContent: [:])
    }
    .padding()
}
