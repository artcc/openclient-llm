//
//  ServerSentEventParser.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 01/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

/// Emits data only at an SSE event boundary, preserving empty lines and all supported line endings.
nonisolated struct ServerSentEventParser {
    private var line: [UInt8] = []
    private var dataLines: [String] = []
    private var previousWasCarriageReturn = false
    private var isFirstLine = true

    mutating func append(_ byte: UInt8) throws -> String? {
        if byte == 0x0A, previousWasCarriageReturn {
            previousWasCarriageReturn = false
            return nil
        }
        previousWasCarriageReturn = byte == 0x0D
        guard byte == 0x0A || byte == 0x0D else {
            line.append(byte)
            return nil
        }
        defer { line.removeAll(keepingCapacity: true) }
        guard var text = String(bytes: line, encoding: .utf8) else { throw APIError.invalidResponse }
        if isFirstLine {
            isFirstLine = false
            if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        }
        if text.isEmpty {
            guard !dataLines.isEmpty else { return nil }
            defer { dataLines.removeAll(keepingCapacity: true) }
            return dataLines.joined(separator: "\n")
        }
        let parts = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.first == "data" else { return nil }
        var value = parts.count == 2 ? parts[1] : Substring()
        if value.first == " " { value = value.dropFirst() }
        dataLines.append(String(value))
        return nil
    }
}
