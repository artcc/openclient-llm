//
//  ImportConversationsImageReferencesTests+Preservation.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

extension ImportConversationsImageReferencesTests {
    func test_execute_nonReferenceContent_preservesUserSystemReasoningPathsAndOtherTools() async throws {
        // Given
        let attachment = image()
        let identifier = attachment.id.uuidString
        let pdf = ChatMessage.Attachment(
            type: .pdf, fileName: "document.pdf", mimeType: "application/pdf",
            fileRelativePath: "", transientData: Data([2])
        )
        let untouched = """
        \(UUID()) \(pdf.id) prefix\(identifier) \(identifier)suffix _\(identifier) \(identifier)_ \
        \(identifier).jpg folder/\(identifier)/photo.jpg C:\\\(identifier) file-\(identifier) \(identifier)-file
        """
        let text = "Reference: (`\(identifier.lowercased())`). \(untouched)"
        let externalArguments = """
        {"question":"\(identifier)","attachment_ids":["\(identifier)"]}
        """
        let calls = ["web_search", "mcp_analyze_images", "generate_image", "list_image_attachments"].map {
            toolCall(name: $0, arguments: externalArguments, id: $0)
        }
        let user = ChatMessage(role: .user, content: text, attachments: [pdf], toolCalls: calls)
        let generation = ChatMessage(role: .tool, content: text, toolCallId: "generation", toolName: "generate_image")
        let original = Conversation(
            title: identifier, modelId: "model", systemPrompt: text,
            contextSummary: text, contextSummaryCursorMessageId: generation.id,
            messages: [
                user,
                ChatMessage(role: .system, content: text),
                ChatMessage(role: .assistant, content: text, reasoningContent: text, attachments: [attachment]),
                ChatMessage(role: .assistant, content: "", toolCalls: calls),
                ChatMessage(role: .tool, content: text, toolCallId: "web_search", toolName: "web_search"),
                ChatMessage(role: .tool, content: text, toolCallId: "mcp", toolName: "mcp_analyze_images"),
                generation
            ]
        )

        // When
        let conversations = try await roundTrip([original])
        let imported = try XCTUnwrap(conversations.first)

        // Then
        let restored = imported.messages[2].attachments[0]
        let expected = "Reference: (`\(restored.id.uuidString)`). \(untouched)"
        XCTAssertEqual(imported.contextSummary, expected)
        XCTAssertEqual(imported.messages[2].content, expected)
        XCTAssertEqual(imported.messages[2].reasoningContent, text)
        XCTAssertEqual(imported.messages[0].content, text)
        XCTAssertEqual(imported.messages[0].toolCalls, calls)
        XCTAssertEqual(imported.messages[1].content, text)
        XCTAssertEqual(imported.messages[3].toolCalls, calls)
        XCTAssertEqual(imported.messages.suffix(3).map(\.content), [text, text, text])
        XCTAssertEqual(imported.systemPrompt, text)
        XCTAssertEqual(imported.title, identifier)
        XCTAssertEqual(restored.fileName, attachment.fileName)
        XCTAssertTrue(restored.fileRelativePath.isEmpty)
        XCTAssertNotEqual(imported.messages[0].attachments[0].id, pdf.id)
    }

    func test_execute_structuredVisualFields_preservesUnknownFieldsAndReferenceOrder() async throws {
        // Given
        let attachment = image()
        let identifier = attachment.id.uuidString
        let unknownId = UUID().uuidString
        let arguments = """
        {"attachment_ids":["\(unknownId)","\(identifier.lowercased())"],
         "question":"Inspect \(identifier); keep \(identifier).jpg",
         "extra":{"id":"\(identifier)","flags":[true,null],"count":123456789012345},"filename":"\(identifier)"}
        """
        let listing = """
        {"image_attachment_ids":["\(unknownId)","\(identifier)"],"offset":3,"total":8,"next_offset":5,
         "extra":"\(identifier)"}
        """
        let analysis = """
        {"untrustedExternalToolResult":"Image \(identifier) is red.","extra":"\(identifier)"}
        """
        let original = Conversation(modelId: "model", messages: [
            ChatMessage(role: .user, content: "Image", attachments: [attachment]),
            ChatMessage(role: .assistant, content: "", toolCalls: [toolCall(arguments: arguments)]),
            ChatMessage(role: .tool, content: analysis, toolCallId: "analysis", toolName: "analyze_images"),
            ChatMessage(role: .tool, content: listing, toolCallId: "list", toolName: "list_image_attachments")
        ])

        // When
        let conversations = try await roundTrip([original])
        let imported = try XCTUnwrap(conversations.first)

        // Then
        let newId = imported.messages[0].attachments[0].id.uuidString
        let importedArguments = try XCTUnwrap(imported.messages[1].toolCalls?.first?.function.arguments)
        XCTAssertEqual(try canonicalJSON(importedArguments), try canonicalJSON("""
        {"attachment_ids":["\(unknownId)","\(newId)"],"question":"Inspect \(newId); keep \(identifier).jpg",
         "extra":{"id":"\(identifier)","flags":[true,null],"count":123456789012345},"filename":"\(identifier)"}
        """))
        XCTAssertEqual(try canonicalJSON(imported.messages[2].content), try canonicalJSON("""
        {"untrustedExternalToolResult":"Image \(newId) is red.","extra":"\(identifier)"}
        """))
        XCTAssertEqual(try canonicalJSON(imported.messages[3].content), try canonicalJSON("""
        {"image_attachment_ids":["\(unknownId)","\(newId)"],"offset":3,"total":8,"next_offset":5,
         "extra":"\(identifier)"}
        """))
    }

    func test_execute_malformedVisualJSON_keepsHistoryImportableAndDoesNotRewriteUnknownFields() async throws {
        // Given
        let attachment = image()
        let identifier = attachment.id.uuidString
        let malformed = "{\"attachment_ids\":[\"\(identifier)\"],\"question\":"
        let malformedList = "{\"image_attachment_ids\":[\"\(identifier)\"]"
        let malformedAnalysis = "{\"untrustedExternalToolResult\":\"\(identifier)"
        let unknownWrapper = "{\"unknown\":\"\(identifier)\"}"
        let original = Conversation(modelId: "model", messages: [
            ChatMessage(role: .user, content: "Image", attachments: [attachment]),
            ChatMessage(role: .assistant, content: "", toolCalls: [toolCall(arguments: malformed)]),
            ChatMessage(role: .tool, content: malformedList, toolName: "list_image_attachments"),
            ChatMessage(role: .tool, content: malformedAnalysis, toolName: "analyze_images"),
            ChatMessage(role: .tool, content: unknownWrapper, toolName: "analyze_images")
        ])

        // When
        let conversations = try await roundTrip([original])
        let imported = try XCTUnwrap(conversations.first)

        // Then
        XCTAssertNotEqual(imported.messages[0].attachments[0].id, attachment.id)
        XCTAssertEqual(imported.messages[1].toolCalls, original.messages[1].toolCalls)
        XCTAssertEqual(imported.messages.suffix(3).map(\.content), original.messages.suffix(3).map(\.content))
    }

    func test_execute_legacyToolResults_usesUnambiguousCallNameAndPreservesExplicitOtherTools() async throws {
        // Given
        let attachment = image()
        let identifier = attachment.id.uuidString
        let calls = [
            toolCall(arguments: "{}"),
            toolCall(name: "list_image_attachments", arguments: "{}", id: "list"),
            toolCall(arguments: "{}", id: "ambiguous"),
            toolCall(name: "external", arguments: "{}", id: "ambiguous")
        ]
        let original = Conversation(modelId: "model", messages: [
            ChatMessage(role: .user, content: "Image", attachments: [attachment]),
            ChatMessage(role: .assistant, content: "", toolCalls: calls),
            ChatMessage(role: .tool, content: "Image \(identifier) is red.", toolCallId: "analysis"),
            ChatMessage(role: .tool, content: "{\"image_attachment_ids\":[\"\(identifier)\"]}", toolCallId: "list"),
            ChatMessage(role: .tool, content: identifier, toolCallId: "analysis", toolName: "external"),
            ChatMessage(role: .tool, content: identifier, toolCallId: "ambiguous"),
            ChatMessage(role: .tool, content: identifier, toolCallId: "missing")
        ])

        // When
        let conversations = try await roundTrip([original])
        let imported = try XCTUnwrap(conversations.first)

        // Then
        let newId = imported.messages[0].attachments[0].id.uuidString
        XCTAssertEqual(imported.messages[2].content, "Image \(newId) is red.")
        XCTAssertEqual(try canonicalJSON(imported.messages[3].content), try canonicalJSON("""
        {"image_attachment_ids":["\(newId)"]}
        """))
        XCTAssertEqual(imported.messages.suffix(3).map(\.content), [identifier, identifier, identifier])
        XCTAssertNil(imported.messages[2].toolName)
    }

    func test_execute_duplicateIDsWithConflictingBytes_preservesPayloadsAndLeavesReferencesUnresolved() async throws {
        // Given
        let first = image(data: Data([1]))
        let second = image(data: Data([2]), id: first.id)
        let call = toolCall(arguments: """
        {"question":"Inspect \(first.id)","attachment_ids":["\(first.id)"]}
        """)
        let assistant = ChatMessage(role: .assistant, content: first.id.uuidString, toolCalls: [call])
        let original = Conversation(
            modelId: "model", contextSummary: first.id.uuidString, contextSummaryCursorMessageId: assistant.id,
            messages: [
                ChatMessage(role: .user, content: "First", attachments: [first]),
                ChatMessage(role: .user, content: "Different bytes", attachments: [second]),
                assistant
            ]
        )

        // When
        let conversations = try await roundTrip([original])
        let imported = try XCTUnwrap(conversations.first)

        // Then
        let restored = imported.messages.flatMap(\.attachments)
        XCTAssertEqual(restored.map(\.transientData), [first.transientData, second.transientData])
        XCTAssertNotEqual(restored[0].id, first.id)
        XCTAssertNotEqual(restored[1].id, first.id)
        XCTAssertNotEqual(restored[0].id, restored[1].id)
        XCTAssertEqual(imported.messages[2].toolCalls, [call])
        XCTAssertEqual(imported.messages[2].content, first.id.uuidString)
        XCTAssertEqual(imported.contextSummary, first.id.uuidString)
    }
}

// MARK: - Lossless JSON

extension ImportConversationsImageReferencesTests {
    func test_execute_unknownNumericFields_preservesExactJSONBytesWhileRemappingSelectedStrings() async throws {
        // Given
        let attachment = image()
        let identifier = attachment.id.uuidString
        let unknown = """
        "extra" : {"attachment_ids":["\(identifier)"],"question":"\(identifier)",
        "untrustedExternalToolResult":"\(identifier)","image_attachment_ids":["\(identifier)"],
        "numbers":[1.2345678901234567890123456789012345678901234567890123456789,1e200,9007199254740993,-0.00E+03],
        "escaped":"\\u0061\\/\\\"","flags":[true,false,null,{},[]]}, "keep":"\(identifier)"
        """
        let payloads: (String) -> [String] = { reference in
            [
                """
                { "attachment_\\u0069ds" : ["\(reference)"], "que\\u0073tion":"Inspect \(reference)",
                \(unknown) }
                """,
                """
                { "image_attachment_ids" : ["\(reference)"], "total":1, \(unknown) }
                """,
                """
                { "untrustedExternalToolResult" : "Image \(reference) is red.", \(unknown) }
                """
            ]
        }
        let source = payloads(identifier)
        let original = Conversation(modelId: "model", messages: [
            ChatMessage(role: .user, content: "Image", attachments: [attachment]),
            ChatMessage(role: .assistant, content: "", toolCalls: [toolCall(arguments: source[0])]),
            ChatMessage(role: .tool, content: source[1], toolName: "list_image_attachments"),
            ChatMessage(role: .tool, content: source[2], toolName: "analyze_images")
        ])

        // When
        let conversations = try await roundTrip([original])
        let imported = try XCTUnwrap(conversations.first)

        // Then
        let expected = payloads(imported.messages[0].attachments[0].id.uuidString)
        let arguments = try XCTUnwrap(imported.messages[1].toolCalls?.first?.function.arguments)
        XCTAssertEqual(Array(arguments.utf8), Array(expected[0].utf8))
        XCTAssertEqual(Array(imported.messages[2].content.utf8), Array(expected[1].utf8))
        XCTAssertEqual(Array(imported.messages[3].content.utf8), Array(expected[2].utf8))
    }

    func test_execute_nestedWrappers_preservesUnknownMembersAtEveryLevelByteForByte() async throws {
        // Given
        let attachment = image()
        let identifier = attachment.id.uuidString
        let wrap: (String) throws -> String = { value in
            let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(value), encoding: .utf8))
            return """
            { "extra": [1e200,1.234567890123456789012345678901234567890123456789],
              "untrustedExternalTool\\u0052esult" : \(encoded), "keep":"\(identifier)" }
            """
        }
        let source = try wrap(wrap("Analysis:\n\(identifier) is red."))
        let original = Conversation(modelId: "model", messages: [
            ChatMessage(role: .user, content: "Image", attachments: [attachment]),
            ChatMessage(role: .tool, content: source, toolName: "analyze_images")
        ])

        // When
        let conversations = try await roundTrip([original])
        let imported = try XCTUnwrap(conversations.first)

        // Then
        let newId = imported.messages[0].attachments[0].id.uuidString
        let expected = try wrap(wrap("Analysis:\n\(newId) is red."))
        XCTAssertEqual(Array(imported.messages[1].content.utf8), Array(expected.utf8))
    }

    func test_execute_nestedAndWronglyTypedReferenceFields_onlyRemapsDirectStringValues() async throws {
        // Given
        let attachment = image()
        let identifier = attachment.id.uuidString
        let arguments: (String) -> String = { reference in
            """
            {"attachment_ids":[["\(identifier)"],{"question":"\(identifier)"},null,1,"\(reference)"],
             "question":{"question":"\(identifier)"}}
            """
        }
        let preserved = [
            "{\"attachment_ids\":\"\(identifier)\",\"question\":[\"\(identifier)\"]}",
            "[{\"attachment_ids\":[\"\(identifier)\"],\"question\":\"\(identifier)\"}]"
        ]
        let original = Conversation(modelId: "model", messages: [
            ChatMessage(role: .user, content: "Image", attachments: [attachment]),
            ChatMessage(role: .assistant, content: "", toolCalls: [toolCall(arguments: arguments(identifier))]),
            ChatMessage(role: .assistant, content: "", toolCalls: preserved.enumerated().map {
                toolCall(arguments: $0.element, id: "preserved-\($0.offset)")
            })
        ])

        // When
        let conversations = try await roundTrip([original])
        let imported = try XCTUnwrap(conversations.first)

        // Then
        let newId = imported.messages[0].attachments[0].id.uuidString
        XCTAssertEqual(imported.messages[1].toolCalls?.first?.function.arguments, arguments(newId))
        XCTAssertEqual(imported.messages[2].toolCalls, original.messages[2].toolCalls)
    }

    func test_execute_malformedTokensAndExcessiveJSONDepth_preservesEntirePayload() async throws {
        // Given
        let attachment = image()
        let identifier = attachment.id.uuidString
        let invalidValues = ["01", "1.", "1e", "+1", "NaN", "true false", "[1,]", "{\"x\":1,}", "\"\\q\""]
        var payloads = invalidValues.map {
            "{\"attachment_ids\":[\"\(identifier)\"],\"extra\":\($0)}"
        }
        let deepValue = String(repeating: "[", count: 129) + "0" + String(repeating: "]", count: 129)
        payloads.append("{\"attachment_ids\":[\"\(identifier)\"],\"extra\":\(deepValue)}")
        payloads.append("{\"attachment_ids\":[\"\(identifier)\"]} trailing")
        let calls = payloads.enumerated().map { toolCall(arguments: $0.element, id: "call-\($0.offset)") }
        let original = Conversation(modelId: "model", messages: [
            ChatMessage(role: .user, content: "Image", attachments: [attachment]),
            ChatMessage(role: .assistant, content: "", toolCalls: calls)
        ])

        // When
        let conversations = try await roundTrip([original])
        let imported = try XCTUnwrap(conversations.first)

        // Then
        XCTAssertNotEqual(imported.messages[0].attachments[0].id, attachment.id)
        XCTAssertEqual(imported.messages[1].toolCalls, calls)
    }

    func test_execute_wrapperDepthLimit_remapsEightLayersAndPreservesDeeperHistory() async throws {
        // Given
        let attachment = image()
        let wrap: (String, Int) -> String = { text, depth in
            (0..<depth).reduce(text) { value, _ in MCPDisplayText.wrappedToolResultForModel(value) }
        }
        let source = [8, 9].map { wrap("Analysis:\n\(attachment.id)", $0) }
        let original = Conversation(modelId: "model", messages: [
            ChatMessage(role: .user, content: "Image", attachments: [attachment])
        ] + source.map { ChatMessage(role: .tool, content: $0, toolName: "analyze_images") })

        // When
        let conversations = try await roundTrip([original])
        let imported = try XCTUnwrap(conversations.first)

        // Then
        let expected = wrap("Analysis:\n\(imported.messages[0].attachments[0].id)", 8)
        XCTAssertEqual(Array(imported.messages[1].content.utf8), Array(expected.utf8))
        XCTAssertEqual(Array(imported.messages[2].content.utf8), Array(source[1].utf8))
    }

    func test_execute_wrappedUnknownOrMalformedJSON_preservesPayloadWithoutTextReplacement() async throws {
        // Given
        let attachment = image()
        let identifier = attachment.id.uuidString
        let payloads = [
            "{\"unknown\":\"\(identifier)\"}",
            "{\"untrustedExternalToolResult\":\"\(identifier)\"",
            "[\"\(identifier)\"]",
            "\"\(identifier)\"",
            "{\"untrustedExternalToolResult\":[\"\(identifier)\"]}"
        ]
        let source = payloads.map { MCPDisplayText.wrappedToolResultForModel($0) }
        let original = Conversation(modelId: "model", messages: [
            ChatMessage(role: .user, content: "Image", attachments: [attachment])
        ] + source.map { ChatMessage(role: .tool, content: $0, toolName: "analyze_images") })

        // When
        let conversations = try await roundTrip([original])
        let imported = try XCTUnwrap(conversations.first)

        // Then
        XCTAssertNotEqual(imported.messages[0].attachments[0].id, attachment.id)
        XCTAssertEqual(imported.messages.dropFirst().map(\.content), source)
    }
}

// MARK: - Private

private extension ImportConversationsImageReferencesTests {
    func canonicalJSON(_ text: String) throws -> Data {
        let value = try JSONDecoder().decode(MCPCallValue.self, from: Data(text.utf8))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}
