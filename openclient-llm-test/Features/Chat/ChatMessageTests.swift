//
//  ChatMessageTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 26/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class ChatMessageTests: XCTestCase {
    func test_codable_imageGenerationAttempt_roundTripsOptionalValues() throws {
        // Given
        let attempts: [Bool?] = [nil, false, true]
        for attempted in attempts {
            let message = ChatMessage(role: .user, content: "Draw a cat", imageGenerationAttempted: attempted)

            // When
            let data = try JSONEncoder().encode(message)
            let restored = try JSONDecoder().decode(ChatMessage.self, from: data)

            // Then
            XCTAssertEqual(restored, message)
            XCTAssertEqual(restored.imageGenerationAttempted, attempted)
            if attempted == nil {
                let text = try XCTUnwrap(String(data: data, encoding: .utf8))
                XCTAssertFalse(text.contains("imageGenerationAttempted"))
            }
        }
    }

    func test_decode_legacyMessageWithoutImageGenerationAttempt_defaultsToNil() throws {
        // Given
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","role":"user","content":"Draw a cat","timestamp":0}
        """

        // When
        let message = try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))

        // Then
        XCTAssertNil(message.imageGenerationAttempted)
    }

    func test_hasSameRequestContent_onlyImageGenerationAttemptChanges_returnsTrue() {
        // Given
        let original = ChatMessage(role: .user, content: "Draw a cat")
        var reserved = original
        reserved.imageGenerationAttempted = true

        // When
        let result = reserved.hasSameRequestContent(as: original)

        // Then
        XCTAssertTrue(result)
        XCTAssertNotEqual(reserved, original)
    }

    func test_hasSameRequestContent_withNormalizedAttachment_returnsTrue() {
        // Given
        let messageId = UUID()
        let attachmentId = UUID()
        let transient = ChatMessage(
            id: messageId,
            role: .user,
            content: "Review this",
            attachments: [.init(
                id: attachmentId,
                type: .pdf,
                fileName: "document.pdf",
                mimeType: "application/pdf",
                fileRelativePath: "",
                transientData: Data("PDF".utf8)
            )]
        )
        let persisted = ChatMessage(
            id: messageId,
            role: .user,
            content: "Review this",
            attachments: [.init(
                id: attachmentId,
                type: .pdf,
                fileName: "document.pdf",
                mimeType: "application/pdf",
                fileRelativePath: "Attachments/conversation/document.pdf"
            )]
        )

        // When
        let result = transient.hasSameRequestContent(as: persisted)

        // Then
        XCTAssertTrue(result)
    }
}
