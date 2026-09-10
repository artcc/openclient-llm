//
//  ListImageAttachmentsToolTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class ListImageAttachmentsToolTests: XCTestCase {
    func test_definition_inventory_declaresOnlyOptionalIntegerOffsetAndDocumentsDiscovery() {
        // Given
        let sut = ListImageAttachmentsTool(attachments: [], isAvailable: { true })

        // When
        let definition = sut.definition
        let parameters = definition.function.parameters

        // Then
        XCTAssertEqual(definition.type, "function")
        XCTAssertEqual(definition.function.name, "list_image_attachments")
        XCTAssertEqual(parameters.type, "object")
        XCTAssertEqual(Set(parameters.properties.keys), ["offset"])
        XCTAssertTrue(parameters.required.isEmpty)
        XCTAssertEqual(parameters.properties["offset"]?.type, "integer")
        XCTAssertNil(parameters.properties["offset"]?.enum)
        guard case .allowed(false) = parameters.additionalProperties else {
            return XCTFail("The inventory must not accept additional arguments")
        }
        XCTAssertTrue(definition.function.description.contains("10"))
        XCTAssertTrue(definition.function.description.contains("chronological"))
        XCTAssertTrue(definition.function.description.contains("compacted history"))
        XCTAssertTrue(definition.function.description.contains("next_offset"))
        XCTAssertTrue(definition.function.description.contains("analyze_images"))
        XCTAssertTrue(parameters.properties["offset"]?.description.contains("omitted") == true)
    }

    func test_definition_oneVersus320Images_hasIdenticalEncodedSchemaAndLength() throws {
        // Given
        let images = makeImages(count: 320)
        let small = ListImageAttachmentsTool(attachments: Array(images.prefix(1)), isAvailable: { true })
        let large = ListImageAttachmentsTool(attachments: images, isAvailable: { true })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        // When
        let smallJSON = try encoder.encode(small.definition)
        let largeJSON = try encoder.encode(large.definition)

        // Then
        XCTAssertFalse(smallJSON.isEmpty)
        XCTAssertEqual(smallJSON.count, largeJSON.count)
        XCTAssertEqual(smallJSON, largeJSON)
        let text = try XCTUnwrap(String(data: largeJSON, encoding: .utf8))
        XCTAssertFalse(text.contains("\"enum\""))
        XCTAssertTrue(images.allSatisfy { !text.contains($0.id.uuidString) })
    }

    func test_execute_omittedOffset_returnsFirstTenIDsInOriginalAttachmentOrder() async throws {
        // Given
        let images = makeImages(count: 23)
        let sut = ListImageAttachmentsTool(attachments: images, isAvailable: { true })

        // When
        let result = try await sut.execute(arguments: "{}")

        // Then
        try assertPage(result, ids: Array(images.prefix(10)).map(\.id), offset: 0, total: 23, nextOffset: 10)
        XCTAssertTrue(result.images.isEmpty)
        XCTAssertNil(result.searchResults)
    }

    func test_execute_middleAndLastPages_preservesOrderAndOmitsNextOffsetAtEnd() async throws {
        // Given
        let images = makeImages(count: 23)
        let sut = ListImageAttachmentsTool(attachments: images, isAvailable: { true })

        // When
        let middle = try await sut.execute(arguments: #"{"offset":10}"#)
        let last = try await sut.execute(arguments: #"{"offset":20}"#)

        // Then
        try assertPage(middle, ids: Array(images[10..<20]).map(\.id), offset: 10, total: 23, nextOffset: 20)
        try assertPage(last, ids: Array(images.suffix(3)).map(\.id), offset: 20, total: 23)
    }

    func test_execute_fullLastPage_omitsNextOffsetEvenWhenTenIDsRemain() async throws {
        // Given
        let images = makeImages(count: 320)
        let sut = ListImageAttachmentsTool(attachments: images, isAvailable: { true })

        // When
        let result = try await sut.execute(arguments: #"{"offset":310}"#)

        // Then
        try assertPage(result, ids: Array(images.suffix(10)).map(\.id), offset: 310, total: 320)
    }

    func test_execute_offsetEqualToTotal_returnsEmptyTerminalPage() async throws {
        // Given
        let sut = ListImageAttachmentsTool(attachments: makeImages(count: 23), isAvailable: { true })

        // When
        let result = try await sut.execute(arguments: #"{"offset":23}"#)

        // Then
        try assertPage(result, ids: [], offset: 23, total: 23)
    }

    func test_execute_emptyOrDocumentOnlyInventory_returnsEmptyPage() async throws {
        // Given
        let document = ChatMessage.Attachment(
            type: .pdf, fileName: "private.pdf", mimeType: "application/pdf", fileRelativePath: "private/file.pdf"
        )

        for inventory in [[], [document]] {
            let sut = ListImageAttachmentsTool(attachments: inventory, isAvailable: { true })

            // When
            let result = try await sut.execute(arguments: "{}")

            // Then
            try assertPage(result, ids: [], offset: 0, total: 0)
        }
    }

    func test_execute_mixedAttachments_excludesDocumentsAndNeverExposesMetadataOrBytes() async throws {
        // Given
        let images = makeImages(count: 2)
        let document = ChatMessage.Attachment(
            type: .pdf, fileName: "private.pdf", mimeType: "application/pdf", fileRelativePath: "private/file.pdf"
        )
        let sut = ListImageAttachmentsTool(attachments: [images[0], document, images[1]], isAvailable: { true })

        // When
        let result = try await sut.execute(arguments: "{}")

        // Then
        try assertPage(result, ids: images.map(\.id), offset: 0, total: 2)
        XCTAssertFalse(result.text.contains(document.id.uuidString))
        for image in images {
            XCTAssertFalse(result.text.contains(image.fileName))
            XCTAssertFalse(result.text.contains(image.fileRelativePath))
            XCTAssertFalse(result.text.contains(image.mimeType))
            XCTAssertFalse(result.text.contains(try XCTUnwrap(image.transientData).base64EncodedString()))
        }
        XCTAssertFalse(result.text.contains("base64"))
        XCTAssertFalse(result.text.contains("data:"))
    }

    func test_execute_invalidJSONTypesAndOutOfBoundsOffsets_rejectsSafelyIncludingIntMax() async {
        // Given
        let sut = ListImageAttachmentsTool(attachments: makeImages(count: 2), isAvailable: { true })
        let inputs = [
            "", "not-json", "[]", "null", "0", #"{"offset":null}"#, #"{"offset":true}"#,
            #"{"offset":"0"}"#, #"{"offset":0.5}"#, #"{"offset":[]}"#, #"{"offset":{}}"#,
            #"{"offset":-1}"#, #"{"offset":3}"#, #"{"offset":0,"limit":10}"#,
            "{\"offset\":\(Int.max)}", "{\"offset\":\(Int.min)}", #"{"offset":9223372036854775808}"#
        ]

        // When / Then
        for input in inputs {
            await assertInvalidOffset(sut, arguments: input)
        }
    }

    func test_execute_argumentByteLimit_accepts1024AndRejects1025() async throws {
        // Given
        let images = makeImages(count: 1)
        let sut = ListImageAttachmentsTool(attachments: images, isAvailable: { true })
        let input = "{}" + String(repeating: " ", count: 1_022)

        // When
        let result = try await sut.execute(arguments: input)

        // Then
        XCTAssertEqual(input.utf8.count, 1_024)
        try assertPage(result, ids: images.map(\.id), offset: 0, total: 1)
        await assertInvalidOffset(sut, arguments: input + " ")
    }

    func test_execute_availabilityRevokedAfterCapture_hidesDefinitionAndRejectsStaleInventory() async {
        // Given
        let availability = AvailabilityState()
        let sut = ListImageAttachmentsTool(attachments: makeImages(count: 1), isAvailable: { availability.value })
        let registry = ToolRegistry(tools: [sut])
        XCTAssertTrue(sut.isAvailableForAdvertisement)
        XCTAssertEqual(registry.definitions.map(\.function.name), ["list_image_attachments"])

        // When
        availability.value = false

        // Then
        XCTAssertFalse(sut.isAvailableForAdvertisement)
        XCTAssertTrue(registry.definitions.isEmpty)
        do {
            _ = try await sut.execute(arguments: "{}")
            XCTFail("A captured inventory must not remain readable after availability is revoked")
        } catch {
            XCTAssertEqual(error as? AnalyzeImagesTool.ExecutionError, .unavailable)
        }
    }

    func test_execute_cancelledTask_throwsCancellationBeforeAvailabilityOrParsing() async {
        // Given
        let sut = ListImageAttachmentsTool(attachments: makeImages(count: 1), isAvailable: { false })

        // When
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await sut.execute(arguments: "not-json")
                XCTFail("A cancelled task must not return an inventory")
            } catch {
                // Then
                XCTAssertTrue(error is CancellationError)
            }
        }
        await task.value
    }

    // MARK: - Private

    private func makeImages(count: Int) -> [ChatMessage.Attachment] {
        (0..<count).map { index in
            ChatMessage.Attachment(
                type: .image, fileName: "private-photo-\(index).jpg", mimeType: "image/jpeg",
                fileRelativePath: "private/images/photo-\(index).jpg", transientData: Data("private-image-bytes".utf8)
            )
        }
    }

    private func assertPage(
        _ result: ToolExecutionResult, ids: [UUID], offset: Int, total: Int, nextOffset: Int? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let data = Data(result.text.utf8)
        let page = try JSONDecoder().decode(Page.self, from: data)
        let fields = try JSONDecoder().decode([String: MCPCallValue].self, from: data)
        var expectedKeys: Set<String> = ["image_attachment_ids", "offset", "total"]
        if nextOffset != nil { expectedKeys.insert("next_offset") }
        XCTAssertEqual(Set(fields.keys), expectedKeys, file: file, line: line)
        XCTAssertEqual(page.imageAttachmentIds, ids.map(\.uuidString), file: file, line: line)
        XCTAssertEqual(page.offset, offset, file: file, line: line)
        XCTAssertEqual(page.total, total, file: file, line: line)
        XCTAssertEqual(page.nextOffset, nextOffset, file: file, line: line)
        XCTAssertLessThanOrEqual(page.imageAttachmentIds.count, 10, file: file, line: line)
    }

    private func assertInvalidOffset(
        _ sut: ListImageAttachmentsTool, arguments: String, file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            _ = try await sut.execute(arguments: arguments)
            XCTFail("Expected invalid offset for \(arguments)", file: file, line: line)
        } catch ListImageAttachmentsTool.ExecutionError.invalidOffset {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    @MainActor
    private final class AvailabilityState {
        var value = true
    }
}

private struct Page: Decodable {
    let imageAttachmentIds: [String]
    let offset: Int
    let total: Int
    let nextOffset: Int?

    enum CodingKeys: String, CodingKey {
        case imageAttachmentIds = "image_attachment_ids"
        case offset, total
        case nextOffset = "next_offset"
    }
}
