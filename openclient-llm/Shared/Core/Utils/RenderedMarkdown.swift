//
//  RenderedMarkdown.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 21/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

nonisolated struct RenderedMarkdown: Equatable, Sendable {
    static let empty = RenderedMarkdown(source: "", blocks: [], inlineContent: [:])

    let source: String
    let blocks: [MessageBlock]
    let inlineContent: [String: AttributedString]
    var footnotes: [MarkdownFootnote] = []

    func attributedString(for source: String) -> AttributedString {
        inlineContent[source] ?? AttributedString(source)
    }
}

nonisolated extension MarkdownParser {
    @concurrent
    static func renderConcurrently(_ source: String) async -> RenderedMarkdown? {
        guard !Task.isCancelled else { return nil }
        let blocks = parse(source)
        guard !Task.isCancelled else { return nil }

        let references = MarkdownFootnoteReferences(blocks: blocks)
        var inlineContent: [String: AttributedString] = [:]
        for content in inlineSources(in: blocks) where inlineContent[content] == nil {
            guard !Task.isCancelled else { return nil }
            inlineContent[content] = attributedString(for: references.replacingReferences(in: content))
            await Task.yield()
        }
        guard !Task.isCancelled else { return nil }
        return RenderedMarkdown(
            source: source,
            blocks: blocks,
            inlineContent: inlineContent,
            footnotes: references.notes
        )
    }
}

private nonisolated extension MarkdownParser {
    static func attributedString(for source: String) -> AttributedString {
        let content = (try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(source)
        return MarkdownScriptParser.applyingScripts(to: content, source: source)
    }
}

nonisolated extension MarkdownParser {
    static func inlineSources(in blocks: [MessageBlock]) -> [String] {
        blocks.flatMap { block -> [String] in
            switch block {
            case .text(let content), .blockquote(let content):
                return [content]
            case .heading(let text, _), .footnote(_, let text):
                return [text]
            case .unorderedList(let items):
                return items.map(\.content)
            case .orderedList(let items):
                return items.map(\.content)
            case .table(let headers, let rows):
                return headers + rows.flatMap { $0 }
            case .taskList(let items):
                return items.map(\.content)
            case .codeBlock, .horizontalRule, .image:
                return []
            }
        }
    }
}
