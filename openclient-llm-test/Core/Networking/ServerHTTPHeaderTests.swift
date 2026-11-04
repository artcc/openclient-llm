//
//  ServerHTTPHeaderTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 02/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class ServerHTTPHeaderTests: XCTestCase {
    func test_validationError_invalidNamesAndReservedHeaders_returnsError() {
        for name in ["", "Bad Name", "Name:", "é", "Authorization", "CONTENT-TYPE", "Host", "Content-Length"] {
            XCTAssertNotNil(ServerHTTPHeader.validationError(in: [.init(name: name, value: "test")]))
        }
    }

    func test_validationError_controlCharactersAndOversizedValues_returnsError() {
        for value in ["a\r\nInjected: value", "a\0b", "a\tb", "a\u{2028}b", String(repeating: "a", count: 8_193)] {
            XCTAssertNotNil(ServerHTTPHeader.validationError(in: [.init(name: "X-Test", value: value)]))
        }
    }

    func test_validationError_duplicateNamesIgnoringCase_returnsError() {
        let headers = [ServerHTTPHeader(name: "X-Test", value: "a"), .init(name: "x-test", value: "b")]
        XCTAssertNotNil(ServerHTTPHeader.validationError(in: headers))
    }

    func test_validationError_providerHeadersAndEmptyValues_acceptsHeaders() {
        let headers = [
            ServerHTTPHeader(name: "x-opencode-session", value: "session-example"),
            .init(name: "User-Agent", value: "OpenClient/1.0.0"),
            .init(name: "X-Empty", value: "")
        ]
        XCTAssertNil(ServerHTTPHeader.validationError(in: headers))
        XCTAssertNil(ServerHTTPHeader.validationError(in: []))
    }

    func test_validationError_excessiveHeaderCountAndTotalSize_returnsError() {
        let headers = (0...ServerHTTPHeader.maximumCount).map { ServerHTTPHeader(name: "X-\($0)", value: "") }
        XCTAssertNotNil(ServerHTTPHeader.validationError(in: headers))
        let oversized = (0..<9).map { ServerHTTPHeader(name: "X-\($0)", value: String(repeating: "a", count: 8_192)) }
        XCTAssertNotNil(ServerHTTPHeader.validationError(in: oversized))
    }

    func test_hasSameValues_differentOrderCaseAndRowIdentity_preservesSemanticEquality() {
        let original = [ServerHTTPHeader(name: "X-One", value: "one"), .init(name: "X-Two", value: "two")]
        let reordered = [ServerHTTPHeader(name: "x-two", value: "two"), .init(name: "x-one", value: "one")]
        XCTAssertTrue(ServerHTTPHeader.hasSameValues(original, reordered))
        XCTAssertFalse(ServerHTTPHeader.hasSameValues(original, [.init(name: "X-One", value: "ONE")]))
    }

    func test_validationError_automaticNameInvalidOrConflicting_rejectsConfiguration() {
        let headers = [ServerHTTPHeader(name: "X-Chat-ID", value: "static")]
        for name in ["", "Bad Name", "Authorization", "x-chat-id", String(repeating: "x", count: 257)] {
            XCTAssertNotNil(ServerHTTPHeader.validationError(in: headers, chatIDHeaderName: name))
        }
        XCTAssertNil(ServerHTTPHeader.validationError(in: headers, chatIDHeaderName: "X-Conversation-ID"))
        XCTAssertNil(ServerHTTPHeader.validationError(in: headers))
    }

    func test_validationError_automaticHeader_countsTowardCombinedLimits() {
        let headers = (0..<ServerHTTPHeader.maximumCount).map { ServerHTTPHeader(name: "X-\($0)") }
        XCTAssertNil(ServerHTTPHeader.validationError(in: headers))
        XCTAssertNotNil(ServerHTTPHeader.validationError(in: headers, chatIDHeaderName: "X-Chat-ID"))
        XCTAssertNil(ServerHTTPHeader.validationError(in: Array(headers.dropLast()), chatIDHeaderName: "X-Chat-ID"))

        // Eight names and values total exactly 65,536 bytes before the automatic header.
        let full = (0..<8).map { ServerHTTPHeader(name: "X-\($0)", value: String(repeating: "a", count: 8_189)) }
        XCTAssertNil(ServerHTTPHeader.validationError(in: full))
        XCTAssertNotNil(ServerHTTPHeader.validationError(in: full, chatIDHeaderName: "X-Chat-ID"))
    }
}
