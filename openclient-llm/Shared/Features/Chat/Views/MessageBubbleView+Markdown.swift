//
//  MessageBubbleView+Markdown.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 21/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

extension MessageBubbleView {
    var unformattedMessageTextView: some View {
        let text = Text(message.content).foregroundColor(.primary)
        let cursor = isStreaming
            ? Text("█").foregroundColor(cursorVisible ? .primary : .clear)
            : Text("")

        return Text("\(text)\(cursor)")
            .accessibilityLabel(Text(verbatim: message.content))
            .accessibilityValue(isStreaming ? String(localized: "Generating response") : "")
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var blocksView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(renderedMarkdown.blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let content):
                    textBlockView(content)
                case .heading(let text, let level):
                    headingBlockView(text, level: level)
                case .codeBlock(let code, let language):
                    CodeBlockView(code: code, language: language)
                case .blockquote(let content):
                    BlockquoteView(content: content, inlineContent: renderedMarkdown.inlineContent)
                case .unorderedList(let items):
                    BulletedListView(items: items, inlineContent: renderedMarkdown.inlineContent)
                case .orderedList(let items):
                    NumberedListView(items: items, inlineContent: renderedMarkdown.inlineContent)
                case .horizontalRule:
                    HorizontalRuleView()
                case .table(let headers, let rows):
                    MarkdownTableView(
                        headers: headers,
                        rows: rows,
                        inlineContent: renderedMarkdown.inlineContent
                    )
                case .taskList(let items):
                    TaskListView(items: items, inlineContent: renderedMarkdown.inlineContent)
                case .image(let alt, let url):
                    MarkdownImageView(alt: alt, urlString: url, onLayoutChanged: onLayoutChanged)
                }
            }
        }
    }

    func renderMarkdownIfNeeded() async {
        guard !isStreaming, !message.content.isEmpty else { return }
        let source = message.content
        guard renderedMarkdown.source != source else { return }
        guard let rendered = await MarkdownParser.renderConcurrently(source),
              !Task.isCancelled else { return }
        renderedMarkdown = rendered
        onLayoutChanged?()
    }

    func textBlockView(_ content: String) -> some View {
        Text(renderedMarkdown.attributedString(for: content))
            .foregroundStyle(Color.primary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    func headingBlockView(_ text: String, level: Int) -> some View {
        Text(text)
            .font(headingFont(level))
            .fontWeight(.semibold)
            .foregroundStyle(Color.primary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title
        case 2: .title2
        case 3: .title3
        default: .headline
        }
    }
}
