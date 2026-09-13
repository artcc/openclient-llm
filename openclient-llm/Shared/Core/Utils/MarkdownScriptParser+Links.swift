//
//  MarkdownScriptParser+Links.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 13/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

nonisolated extension MarkdownScriptParser {
    static func applyingScripts(to content: AttributedString, source: String) -> AttributedString {
        let scripted = applyingScripts(to: content)
        guard source.range(of: "<su", options: .caseInsensitive) != nil else { return scripted }
        return restoringLinkScripts(in: scripted, source: source)
    }
}

// MARK: - Private

private nonisolated extension MarkdownScriptParser {
    nonisolated struct InlineLink {
        let source: String
        let label: String
    }

    static func restoringLinkScripts(in content: AttributedString, source: String) -> AttributedString {
        let text = String(content.characters)
        var searchStart = text.startIndex
        var replacements: [(Range<AttributedString.Index>, AttributedString)] = []
        for link in inlineLinks(in: source) {
            guard let parsed = parseInline(link.source), let url = parsed.link,
                  let range = matchingLinkRange(
                    String(parsed.characters), url: url, in: content, text: text, searchStart: &searchStart
                  ) else { continue }
            guard let label = parseInline(link.label) else { continue }
            let formatted = applyingScripts(to: label)
            guard formatted.runs.contains(where: { $0[MarkdownScriptAttribute.self] != nil }) else { continue }

            // Foundation can flatten a link label's HTML and emphasis attributes. Parse the original
            // label on its own, then restore the link and any formatting inherited from outside it.
            let inherited = content[range].runs.first?.attributes ?? AttributeContainer()
            replacements.append((range, inheritingAttributes(inherited, in: formatted)))
        }
        var result = content
        for (range, replacement) in replacements.reversed() {
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    static func matchingLinkRange(
        _ label: String,
        url: URL,
        in content: AttributedString,
        text: String,
        searchStart: inout String.Index
    ) -> Range<AttributedString.Index>? {
        guard !label.isEmpty else { return nil }
        var cursor = searchStart
        while let range = text.range(of: label, options: .literal, range: cursor..<text.endIndex) {
            let lower = content.characters.index(content.startIndex, offsetBy: text[..<range.lowerBound].count)
            let upper = content.characters.index(lower, offsetBy: text[range].count)
            if content[lower..<upper].runs.allSatisfy({ $0.link == url }) {
                searchStart = range.upperBound
                return lower..<upper
            }
            cursor = range.upperBound
        }
        return nil
    }

    static func inheritingAttributes(
        _ attributes: AttributeContainer,
        in content: AttributedString
    ) -> AttributedString {
        var result = content
        result.mergeAttributes(attributes, mergePolicy: .keepCurrent)
        let inheritedIntent = attributes.inlinePresentationIntent ?? []
        if !inheritedIntent.isEmpty {
            for run in result.runs {
                result[run.range].inlinePresentationIntent = (run.inlinePresentationIntent ?? []).union(inheritedIntent)
            }
        }
        return result
    }

    static func parseInline(_ source: String) -> AttributedString? {
        try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
    }

    static func inlineLinks(in source: String) -> [InlineLink] {
        // Consume escapes and code before recognizing link labels. Include images to skip their destinations.
        let pattern = #"(?s)(?<!`)(`+)(?!`).*?\1(?!`)|\\.|<!--.*?-->|<(?:[^<>"']|"[^"]*"|'[^']*')*>"#
            + #"|(!?)\[((?:\\.|[^\[\]\\\n]|\[[^\]\n]*\])*)\]\("#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var links: [InlineLink] = []
        var destinationEnd = source.startIndex
        for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            guard match.range(at: 3).location != NSNotFound,
                  let range = Range(match.range, in: source), range.lowerBound >= destinationEnd,
                  let labelRange = Range(match.range(at: 3), in: source),
                  let end = linkDestinationEnd(in: source, from: range.upperBound) else { continue }
            destinationEnd = end
            guard match.range(at: 2).length == 0 else { continue }
            links.append(InlineLink(source: String(source[range.lowerBound..<end]), label: String(source[labelRange])))
        }
        return links
    }

    static func linkDestinationEnd(in source: String, from startIndex: String.Index) -> String.Index? {
        var index = startIndex
        var depth = 1
        var quote: Character?
        while index < source.endIndex {
            let character = source[index]
            index = source.index(after: index)
            if character == "\\", index < source.endIndex {
                index = source.index(after: index)
            } else if let delimiter = quote {
                if character == delimiter { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }
}
