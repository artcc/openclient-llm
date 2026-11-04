//
//  ServerHTTPHeader.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 02/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

nonisolated struct ServerHTTPHeader: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String = ""
    var value: String = ""

    static let maximumCount = 32

    private static let reservedNames: Set<String> = [
        "authorization", "proxy-authorization", "host", "content-type", "content-length",
        "connection", "transfer-encoding", "trailer", "te", "upgrade"
    ]

    var nameError: String? {
        let punctuation = "!#$%&'*+-.^_`|~".utf8
        guard !name.isEmpty, name.utf8.count <= 256,
              name.utf8.allSatisfy({ byte in
                  (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
                      || punctuation.contains(byte)
              }) else {
            return String(localized: "Enter a valid HTTP header name without spaces.")
        }
        guard !Self.reservedNames.contains(name.lowercased()) else {
            return String(localized: "This header is managed by the app or the HTTP transport.")
        }
        return nil
    }

    var valueError: String? {
        guard value.utf8.count <= 8_192 else {
            return String(localized: "The header value is too long.")
        }
        let forbiddenCharacters = CharacterSet.controlCharacters.union(.newlines)
        guard !value.unicodeScalars.contains(where: { forbiddenCharacters.contains($0) }) else {
            return String(localized: "Header values cannot contain line breaks or control characters.")
        }
        return nil
    }

    static func validationError(in headers: [Self], chatIDHeaderName: String? = nil) -> String? {
        let automaticHeaderBytes = chatIDHeaderName.map { $0.utf8.count + 36 } ?? 0
        guard headers.count + (chatIDHeaderName == nil ? 0 : 1) <= maximumCount,
              headers.reduce(automaticHeaderBytes, { $0 + $1.name.utf8.count + $1.value.utf8.count }) <= 65_536 else {
            return String(localized: "The custom headers exceed the allowed size or number.")
        }
        var names = Set<String>()
        for header in headers {
            if let error = header.nameError ?? header.valueError { return error }
            guard names.insert(header.name.lowercased()).inserted else {
                return String(localized: "Header names must be unique, regardless of capitalization.")
            }
        }
        return chatIDHeaderNameError(chatIDHeaderName, in: headers)
    }

    static func chatIDHeaderNameError(_ name: String?, in headers: [Self]) -> String? {
        guard let name else { return nil }
        if let error = Self(name: name).nameError { return error }
        guard !headers.contains(where: { $0.name.lowercased() == name.lowercased() }) else {
            return String(localized: "Header names must be unique, regardless of capitalization.")
        }
        return nil
    }

    static func hasSameValues(_ lhs: [Self], _ rhs: [Self]) -> Bool {
        let left = lhs.map { "\($0.name.lowercased()):\($0.value)" }.sorted()
        let right = rhs.map { "\($0.name.lowercased()):\($0.value)" }.sorted()
        return left == right
    }

    static func apply(
        _ headers: [Self], to request: inout URLRequest, chatIDHeaderName: String? = nil, chatID: UUID? = nil
    ) throws {
        if let error = validationError(in: headers, chatIDHeaderName: chatIDHeaderName) {
            throw APIError.invalidRequest(error)
        }
        for header in headers {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        if let chatIDHeaderName, let chatID {
            request.setValue(chatID.uuidString, forHTTPHeaderField: chatIDHeaderName)
        }
    }
}
