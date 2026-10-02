//
//  ImageOperationAttemptTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 01/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class ImageOperationAttemptTests: XCTestCase {
    func test_init_reservationWithoutTranscript_preservesOperationAcrossCodable() throws {
        for operation in [ChatMessage.ImageOperation.generation, .editing, .unknown] {
            // Given
            let user = ChatMessage(
                role: .user, content: "Image", imageGenerationAttempted: true, imageOperationAttempted: operation
            )

            // When
            let restored = try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(user))
            let attempt = ImageOperationAttempt(messages: [restored])

            // Then
            XCTAssertEqual(restored.imageOperationAttempted, operation)
            XCTAssertTrue(attempt.wasAttempted)
            XCTAssertEqual(attempt.preventsNativeRestart, operation != .generation)
            XCTAssertTrue(user.hasSameRequestContent(as: ChatMessage(id: user.id, role: .user, content: user.content)))
        }
    }

    func test_init_legacyFlagWithoutTranscript_neverAssumesGeneration() {
        // Given / When
        let attempt = ImageOperationAttempt(messages: [
            ChatMessage(role: .user, content: "Image", imageGenerationAttempted: true)
        ])

        // Then
        XCTAssertTrue(attempt.wasAttempted)
        XCTAssertEqual(attempt.operation, .unknown)
        XCTAssertTrue(attempt.preventsNativeRestart)
    }

    func test_init_resultWithoutToolName_resolvesIdentityWithinCurrentTurn() {
        for name in ["generate_image", "edit_image"] {
            // Given
            let call = ToolCall(id: "image", type: "function", function: .init(name: name, arguments: "{}"))
            let messages = [
                ChatMessage(role: .user, content: "Image"),
                ChatMessage(role: .assistant, content: "", toolCalls: [call]),
                ChatMessage(role: .tool, content: "Result", toolCallId: call.id)
            ]

            // When
            let attempt = ImageOperationAttempt(messages: messages)

            // Then
            XCTAssertTrue(attempt.wasAttempted)
            XCTAssertEqual(attempt.operation, name == "edit_image" ? .editing : .generation)
        }
    }

    func test_init_ambiguousGenerationResult_keepsReservationWithoutAssumingNativeRestart() {
        // Given
        let calls = ["generate_image", "get_current_datetime"].map {
            ToolCall(id: "ambiguous", type: "function", function: .init(name: $0, arguments: "{}"))
        }

        // When
        let attempt = ImageOperationAttempt(messages: [
            ChatMessage(role: .user, content: "Image"),
            ChatMessage(role: .assistant, content: "", toolCalls: calls),
            ChatMessage(role: .tool, content: "Result", toolCallId: "ambiguous")
        ])

        // Then
        XCTAssertEqual(attempt.operation, .unknown)
        XCTAssertTrue(attempt.preventsNativeRestart)
    }

    func test_init_newUserTurn_doesNotInheritEarlierReservationOrCalls() {
        // Given / When
        let attempt = ImageOperationAttempt(messages: [
            ChatMessage(
                role: .user, content: "Edit", imageGenerationAttempted: true, imageOperationAttempted: .editing
            ),
            ChatMessage(role: .tool, content: "Edited", toolCallId: "image", toolName: "edit_image"),
            ChatMessage(role: .user, content: "A new image")
        ])

        // Then
        XCTAssertFalse(attempt.wasAttempted)
        XCTAssertFalse(attempt.preventsNativeRestart)
    }

    func test_decode_futureOperation_doesNotLoseTheReservation() throws {
        // Given
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","role":"user","content":"Image","timestamp":0,
         "imageGenerationAttempted":true,"imageOperationAttempted":"future-operation"}
        """

        // When
        let message = try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))

        // Then
        XCTAssertEqual(message.imageOperationAttempted, .unknown)
        XCTAssertTrue(ImageOperationAttempt(messages: [message]).preventsNativeRestart)
    }
}
