//
//  MarkdownInlineText.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 13/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct MarkdownInlineText: View {
    @Environment(\.font) private var font
    @Environment(\.fontResolutionContext) private var fontResolutionContext

    let content: AttributedString

    init(_ content: AttributedString) {
        self.content = content
    }

    var body: some View {
        Text(styledContent)
    }

    private var styledContent: AttributedString {
        var result = content
        for run in content.runs {
            guard let position = run[MarkdownScriptAttribute.self] else { continue }
            let baseFont = run.font ?? font ?? .body
            let pointSize = baseFont.resolve(in: fontResolutionContext).pointSize
            result[run.range].font = baseFont.scaled(by: 0.75)
            result[run.range].baselineOffset = pointSize * (position > 0 ? 0.35 : -0.2)
        }
        return result
    }
}

#Preview("Subscripts and superscripts") {
    var subscriptText = AttributedString("2")
    subscriptText[MarkdownScriptAttribute.self] = -1
    var superscriptText = AttributedString("n + 1")
    superscriptText[MarkdownScriptAttribute.self] = 1
    let content = AttributedString("H") + subscriptText + AttributedString("O and x") + superscriptText

    return VStack(alignment: .leading, spacing: 16) {
        MarkdownInlineText(content).font(.body)
        MarkdownInlineText(content).font(.title2)
        MarkdownInlineText(content).font(.footnote)
        MarkdownInlineText(content).font(.body).environment(\.dynamicTypeSize, .accessibility3)
    }
    .padding()
}
