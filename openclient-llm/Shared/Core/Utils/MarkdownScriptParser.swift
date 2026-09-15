//
//  MarkdownScriptParser.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 13/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

nonisolated enum MarkdownScriptParser {
    static func applyingScripts(to content: AttributedString) -> AttributedString {
        let pairs = matchingPairs(in: content)
        guard !pairs.isEmpty else { return content }
        var result = content

        // Apply outer spans first, allowing an inner sub/sup to select its own position.
        for pair in pairs.reversed() {
            result[pair.opening.range.upperBound..<pair.closing.range.lowerBound][MarkdownScriptAttribute.self] =
                pair.opening.name == "sup" ? 1 : -1
        }
        let tagRanges = pairs.flatMap { [$0.opening.range, $0.closing.range] }
            .sorted { $0.lowerBound > $1.lowerBound }
        for range in tagRanges {
            result.removeSubrange(range)
        }
        return result
    }
}

// MARK: - Private

private nonisolated extension MarkdownScriptParser {
    nonisolated struct Tag {
        let name: String
        let isClosing: Bool
        let range: Range<AttributedString.Index>
    }

    nonisolated struct Pair {
        let opening: Tag
        let closing: Tag
    }

    static func matchingPairs(in content: AttributedString) -> [Pair] {
        var stack: [Tag] = []
        var pairs: [Pair] = []
        for tag in tags(in: content) {
            if !tag.isClosing {
                stack.append(tag)
            } else if let opening = stack.last, opening.name == tag.name {
                stack.removeLast()
                pairs.append(Pair(opening: opening, closing: tag))
            } else {
                // Crossed or unmatched tags stay literal instead of consuming surrounding text.
                stack.removeAll()
            }
        }
        return pairs
    }

    static func tags(in content: AttributedString) -> [Tag] {
        let pattern = #"(?s)</?(sub|sup)\s*>|<!--.*?-->|<(?:[^<>"']|"[^"]*"|'[^']*')*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }
        var tags: [Tag] = []
        for run in content.runs {
            // Foundation identifies HTML in ordinary text; link labels are recovered separately from source.
            guard run.inlinePresentationIntent?.contains(.inlineHTML) == true else { continue }
            let text = String(content[run.range].characters)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard match.range(at: 1).location != NSNotFound,
                      let range = Range(match.range, in: text),
                      let nameRange = Range(match.range(at: 1), in: text) else { continue }
                let lower = content.characters.index(run.range.lowerBound, offsetBy: text[..<range.lowerBound].count)
                let upper = content.characters.index(lower, offsetBy: text[range].count)
                tags.append(Tag(
                    name: text[nameRange].lowercased(),
                    isClosing: text[range].hasPrefix("</"),
                    range: lower..<upper
                ))
            }
        }
        return tags
    }
}
