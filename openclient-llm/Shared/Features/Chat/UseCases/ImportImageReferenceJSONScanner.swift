//
//  ImportImageReferenceJSONScanner.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

struct ImportImageReferenceJSONScanner {
    private enum ScanError: Error {
        case invalidJSON
    }

    private struct Token {
        let key: String
        let range: Range<Int>
        let value: String
    }

    private let bytes: [UInt8]
    private let idsKey: String?
    private let textKey: String?
    private var offset = 0
    private var tokens: [Token] = []

    init(text: String, idsKey: String?, textKey: String?) {
        bytes = Array(text.utf8)
        self.idsKey = idsKey
        self.textKey = textKey
    }

    mutating func transform(_ replacement: (String, String) -> String) throws -> String {
        skipWhitespace()
        guard bytes.indices.contains(offset), bytes[offset] == 0x7B else { throw ScanError.invalidJSON }
        try scanValue(depth: 0)
        skipWhitespace()
        guard offset == bytes.count else { throw ScanError.invalidJSON }

        // Only selected string tokens are encoded. All other bytes, including arbitrary numbers, stay untouched.
        var result = Data()
        var copiedThrough = 0
        for token in tokens {
            let value = replacement(token.key, token.value)
            guard value != token.value else { continue }
            result.append(contentsOf: bytes[copiedThrough..<token.range.lowerBound])
            result.append(try JSONEncoder().encode(value))
            copiedThrough = token.range.upperBound
        }
        result.append(contentsOf: bytes[copiedThrough...])
        guard let text = String(data: result, encoding: .utf8) else { throw ScanError.invalidJSON }
        return text
    }

    // MARK: - Private

    private mutating func scanValue(depth: Int, stringKey: String? = nil, arrayKey: String? = nil) throws {
        skipWhitespace()
        // Deep or malformed embedded JSON is left unchanged by the caller, not rejected as a backup.
        guard depth <= 128, bytes.indices.contains(offset) else { throw ScanError.invalidJSON }
        switch bytes[offset] {
        case 0x7B:
            try scanObject(depth: depth)
        case 0x5B:
            try scanArray(depth: depth, stringKey: arrayKey)
        case 0x22:
            let start = offset
            let value = try scanString()
            if let stringKey {
                tokens.append(Token(key: stringKey, range: start..<offset, value: value))
            }
        default:
            try scanLiteral()
        }
    }

    private mutating func scanObject(depth: Int) throws {
        offset += 1
        if consume(0x7D) { return }
        repeat {
            skipWhitespace()
            let key = try scanString()
            guard consume(0x3A) else { throw ScanError.invalidJSON }
            try scanValue(
                depth: depth + 1,
                stringKey: depth == 0 && key == textKey ? key : nil,
                arrayKey: depth == 0 && key == idsKey ? key : nil
            )
            if consume(0x7D) { return }
        } while consume(0x2C)
        throw ScanError.invalidJSON
    }

    private mutating func scanArray(depth: Int, stringKey: String?) throws {
        offset += 1
        if consume(0x5D) { return }
        repeat {
            try scanValue(depth: depth + 1, stringKey: stringKey)
            if consume(0x5D) { return }
        } while consume(0x2C)
        throw ScanError.invalidJSON
    }

    private mutating func scanString() throws -> String {
        guard bytes.indices.contains(offset), bytes[offset] == 0x22 else { throw ScanError.invalidJSON }
        let start = offset
        offset += 1
        while offset < bytes.count {
            switch bytes[offset] {
            case 0x22:
                offset += 1
                return try JSONDecoder().decode(String.self, from: Data(bytes[start..<offset]))
            case 0x5C:
                offset += 2
            default:
                offset += 1
            }
        }
        throw ScanError.invalidJSON
    }

    private mutating func scanLiteral() throws {
        let start = offset
        while offset < bytes.count, ![0x20, 0x09, 0x0A, 0x0D, 0x2C, 0x5D, 0x7D].contains(bytes[offset]) {
            offset += 1
        }
        guard let literal = String(bytes: bytes[start..<offset], encoding: .utf8) else {
            throw ScanError.invalidJSON
        }
        if ["true", "false", "null"].contains(literal) { return }
        let numberPattern = #"\A-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?\z"#
        guard literal.range(of: numberPattern, options: .regularExpression) != nil else {
            throw ScanError.invalidJSON
        }
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        skipWhitespace()
        guard bytes.indices.contains(offset), bytes[offset] == byte else { return false }
        offset += 1
        return true
    }

    private mutating func skipWhitespace() {
        while offset < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[offset]) {
            offset += 1
        }
    }
}
