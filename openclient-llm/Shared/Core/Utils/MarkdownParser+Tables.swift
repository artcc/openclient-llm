//
//  MarkdownParser+Tables.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 13/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

nonisolated extension MarkdownParser {
    static func tryParseTable(lines: [String], startIndex: Int) -> MessageBlock? {
        guard startIndex + 1 < lines.count else { return nil }

        let headers = parseTableRow(lines[startIndex])
        guard !headers.isEmpty,
              isTableSeparator(lines[startIndex + 1], columnCount: headers.count) else { return nil }

        var rows: [[String]] = []
        var index = startIndex + 2
        while index < lines.count {
            if isTableBodyBoundary(lines[index]) { break }
            let row = parseTableRow(lines[index])
            if row.isEmpty { break }
            rows.append(row)
            index += 1
        }
        return .table(headers: headers, rows: rows)
    }

    static func advancePastTable(lines: [String], startIndex: Int) -> Int {
        var index = startIndex + 2
        while index < lines.count && !isTableBodyBoundary(lines[index]) && !parseTableRow(lines[index]).isEmpty {
            index += 1
        }
        return index
    }
}

// MARK: - Private

private nonisolated extension MarkdownParser {
    static func parseTableRow(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var cells: [String] = []
        var cell = ""
        var index = trimmed.startIndex
        var endsWithSeparator = false

        while index < trimmed.endIndex {
            let character = trimmed[index]
            index = trimmed.index(after: index)
            endsWithSeparator = false
            if character == "\\", index < trimmed.endIndex {
                // Escaped pipes are cell content, including inside inline code.
                if trimmed[index] != "|" { cell.append(character) }
                cell.append(trimmed[index])
                index = trimmed.index(after: index)
            } else if character == "|" {
                cells.append(cell.trimmingCharacters(in: .whitespaces))
                cell = ""
                endsWithSeparator = true
            } else {
                cell.append(character)
            }
        }

        guard !cells.isEmpty else { return [] }
        if !endsWithSeparator { cells.append(cell.trimmingCharacters(in: .whitespaces)) }
        if trimmed.hasPrefix("|") { cells.removeFirst() }
        return cells
    }

    static func isTableSeparator(_ line: String, columnCount: Int) -> Bool {
        let cells = parseTableRow(line)
        guard cells.count == columnCount else { return false }

        return cells.allSatisfy { cell in
            var marker = cell[...]
            if marker.hasPrefix(":") { marker = marker.dropFirst() }
            if marker.hasSuffix(":") { marker = marker.dropLast() }
            return !marker.isEmpty && marker.allSatisfy { $0 == "-" }
        }
    }
}
