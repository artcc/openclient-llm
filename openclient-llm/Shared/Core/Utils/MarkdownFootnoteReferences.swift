//
//  MarkdownFootnoteReferences.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 13/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

nonisolated struct MarkdownFootnoteReferences: Sendable {
    let notes: [MarkdownFootnote]
    private let numbers: [String: Int]

    init(blocks: [MessageBlock]) {
        var definitions: [String: String] = [:]
        var labels: [String] = []
        for case .footnote(let label, let content) in blocks where definitions[label] == nil {
            definitions[label] = content
            labels.append(label)
        }
        guard !definitions.isEmpty else {
            self.numbers = [:]
            notes = []
            return
        }

        var numbers: [String: Int] = [:]
        let bodyBlocks = blocks.filter {
            if case .footnote = $0 { return false }
            return true
        }
        let sources = MarkdownParser.inlineSources(in: bodyBlocks) + labels.compactMap { definitions[$0] }
        for source in sources {
            for match in Self.referenceMatches(in: source) {
                guard let range = Range(match.range(at: 2), in: source) else { continue }
                let label = String(source[range])
                if definitions[label] != nil && numbers[label] == nil {
                    numbers[label] = numbers.count + 1
                }
            }
        }
        for label in labels where numbers[label] == nil {
            numbers[label] = numbers.count + 1
        }
        self.numbers = numbers
        notes = labels.compactMap { label -> MarkdownFootnote? in
            guard let number = numbers[label], let content = definitions[label] else { return nil }
            return MarkdownFootnote(number: number, label: label, content: content)
        }.sorted { $0.number < $1.number }
    }

    func replacingReferences(in source: String) -> String {
        guard !numbers.isEmpty else { return source }
        var result = source
        for match in Self.referenceMatches(in: source).reversed() {
            guard let labelRange = Range(match.range(at: 2), in: source),
                  let number = numbers[String(source[labelRange])],
                  let range = Range(match.range, in: result) else { continue }
            let digits = ["⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"]
            let superscript = String(number).compactMap(\.wholeNumberValue).map { digits[$0] }.joined()
            result.replaceSubrange(range, with: superscript)
        }
        return result
    }
}

// MARK: - Private

private nonisolated extension MarkdownFootnoteReferences {
    static func referenceMatches(in source: String) -> [NSTextCheckingResult] {
        guard source.contains("[^") else { return [] }
        // Consume code spans, escapes and link labels before looking for references.
        let pattern = #"(?s)(?<!`)(`+)(?!`).*?\1(?!`)|\\.|!?\[(?:[^\[\]\n]|\[[^\]\n]*\])*\]\(|<[^>\n]*>"#
            + #"|\[\^([^\]\s\[]+)\](?![(:])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var references: [NSTextCheckingResult] = []
        var destinationEnd = source.startIndex
        for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            guard let range = Range(match.range, in: source), range.lowerBound >= destinationEnd else { continue }
            if match.range(at: 2).location != NSNotFound {
                references.append(match)
            } else if source[range].hasSuffix("](") {
                destinationEnd = endOfLinkDestination(in: source, from: range.upperBound)
            }
        }
        return references
    }

    static func endOfLinkDestination(in source: String, from startIndex: String.Index) -> String.Index {
        var index = startIndex
        var depth = 1
        while index < source.endIndex {
            let character = source[index]
            index = source.index(after: index)
            if character == "\\", index < source.endIndex {
                index = source.index(after: index)
            } else if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return source.endIndex
    }
}
