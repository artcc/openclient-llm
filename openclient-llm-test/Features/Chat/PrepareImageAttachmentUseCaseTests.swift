//
//  PrepareImageAttachmentUseCaseTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 09/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import openclient_llm

@MainActor
final class PrepareImageAttachmentUseCaseTests: XCTestCase {
    // MARK: - Tests

    func test_execute_tiffImage_returnsBoundedJPEG() async throws {
        // Given
        let sut = PrepareImageAttachmentUseCase()
        let input = try makeImageData(type: .tiff)

        // When
        let result = try await sut.execute(data: input, fileName: "capture.dng")

        // Then
        XCTAssertEqual(result.mimeType, "image/jpeg")
        XCTAssertEqual(result.fileName, "capture.jpg")
        XCTAssertEqual(Array(result.data.prefix(2)), [0xFF, 0xD8])
        XCTAssertLessThanOrEqual(result.data.count, 5_000_000)
    }

    func test_execute_supportedPNG_preservesDataAndCorrectsExtension() async throws {
        // Given
        let sut = PrepareImageAttachmentUseCase()
        let input = try makeImageData(type: .png)

        // When
        let result = try await sut.execute(data: input, fileName: "photo.jpg")

        // Then
        XCTAssertEqual(result.data, input)
        XCTAssertEqual(result.mimeType, "image/png")
        XCTAssertEqual(result.fileName, "photo.png")
    }

    func test_execute_gifWithDefaultConfiguration_preservesOriginalForChat() async throws {
        // Given
        let input = try makeImageData(type: .gif)
        let sut = PrepareImageAttachmentUseCase()

        // When
        let result = try await sut.execute(data: input, fileName: "animation.gif")

        // Then
        XCTAssertEqual(result.data, input)
        XCTAssertEqual(result.mimeType, "image/gif")
        XCTAssertEqual(result.fileName, "animation.gif")
    }

    func test_execute_gifForImageEditing_convertsToBoundedJPEG() async throws {
        // Given
        let input = try makeImageData(type: .gif)
        let sut = PrepareImageAttachmentUseCase(preservesGIF: false)

        // When
        let result = try await sut.execute(data: input, fileName: "animation.gif")

        // Then
        XCTAssertEqual(result.mimeType, "image/jpeg")
        XCTAssertEqual(result.fileName, "animation.jpg")
        XCTAssertEqual(Array(result.data.prefix(2)), [0xFF, 0xD8])
        XCTAssertLessThanOrEqual(result.data.count, ImageAttachmentConstraints.maximumBytes)
    }

    func test_execute_invalidData_throwsError() async {
        // Given
        let sut = PrepareImageAttachmentUseCase()
        let input = Data("not an image".utf8)

        // When
        do {
            _ = try await sut.execute(data: input, fileName: "photo.raw")
            XCTFail("Expected image preparation to fail")
        } catch {
            // Then
            XCTAssertNotNil(error as? LocalizedError)
        }
    }
}

// MARK: - Private

private extension PrepareImageAttachmentUseCaseTests {
    func makeImageData(type: UTType) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 16,
            height: 12,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 12))
        let image = try XCTUnwrap(context.makeImage())

        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            output,
            type.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }
}
