//
//  MarkdownParser+Footnotes.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 13/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

nonisolated extension MarkdownParser {
    static func footnoteCodeLines(in lines: [String]) -> Set<Int> {
        guard lines.contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[^") }) else { return [] }
        let source = lines.joined(separator: "\n")
        // Definitions inside multiline code spans must remain literal Markdown examples.
        let pattern = #"(?s)\\.|(?<!`)(`+)(?!`).*?\1(?!`)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ranges = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
            .filter { $0.range(at: 1).location != NSNotFound }
            .map(\.range)
        var protectedLines: Set<Int> = []
        var offset = 0
        var rangeIndex = 0
        for (lineIndex, line) in lines.enumerated() {
            let contentOffset = offset + line.prefix(while: { $0 == " " }).count
            while rangeIndex < ranges.count && NSMaxRange(ranges[rangeIndex]) <= contentOffset {
                rangeIndex += 1
            }
            if rangeIndex < ranges.count && NSLocationInRange(contentOffset, ranges[rangeIndex]) {
                protectedLines.insert(lineIndex)
            }
            offset += line.utf16.count + 1
        }
        return protectedLines
    }

    static func parseFootnote(lines: [String], startIndex: inout Int) -> MessageBlock? {
        let line = lines[startIndex]
        let indentation = line.prefix(while: { $0 == " " }).count
        let trimmed = line.dropFirst(indentation)
        guard indentation < 4, trimmed.hasPrefix("[^"),
              let end = trimmed.range(of: "]:") else { return nil }
        let label = String(trimmed.dropFirst(2).prefix(upTo: end.lowerBound))
        guard !label.isEmpty, !label.contains(where: { $0.isWhitespace || $0 == "[" || $0 == "]" }) else {
            return nil
        }

        var content = [String(trimmed[end.upperBound...].drop(while: { $0 == " " || $0 == "\t" }))]
        var index = startIndex + 1
        while index < lines.count {
            if let continuation = footnoteContinuation(lines[index]) {
                content.append(continuation)
                index += 1
            } else if lines[index].trimmingCharacters(in: .whitespaces).isEmpty,
                      index + 1 < lines.count, footnoteContinuation(lines[index + 1]) != nil {
                content.append("")
                index += 1
            } else if content.last?.hasSuffix("  ") == true,
                      !lines[index].trimmingCharacters(in: .whitespaces).isEmpty,
                      !isTableBodyBoundary(lines[index]) {
                content.append(lines[index])
                index += 1
            } else {
                break
            }
        }

        let text = content.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        startIndex = index
        return .footnote(label: label, content: text)
    }
}

private nonisolated extension MarkdownParser {
    static func footnoteContinuation(_ line: String) -> String? {
        if line.hasPrefix("    ") { return String(line.dropFirst(4)) }
        if line.hasPrefix("\t") { return String(line.dropFirst()) }
        return nil
    }
}
