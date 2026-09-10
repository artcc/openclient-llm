//
//  GeneratedImageDecoderTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import UIKit
import XCTest
@testable import openclient_llm

@MainActor
final class GeneratedImageDecoderTests: XCTestCase {
    func test_decode_dataURL_usesImageBytesRatherThanDeclaredMIME() throws {
        // Given
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let png = try XCTUnwrap(image.pngData())
        let jpeg = try XCTUnwrap(image.jpegData(compressionQuality: 0.8))
        let cases = [(png, "image/png"), (jpeg, "image/jpeg")]
        for (data, mimeType) in cases {
            let url = "data:image/gif;base64,\(data.base64EncodedString())"

            // When
            let decoded = try GeneratedImageDecoder.decode(dataURL: url)

            // Then
            XCTAssertEqual(decoded.data, data)
            XCTAssertEqual(decoded.mimeType, mimeType)
            XCTAssertNil(decoded.revisedPrompt)
        }
    }

    func test_decode_invalidOrRemoteDataURL_rejectsWithoutDownloading() {
        // Given
        let urls = [
            "https://example.com/image.png", "file:///image.png", "", "data:image/png;base64,",
            "data:image/png;base64,!!!!", "data:image/png;base64,A", "data:image/png,AAAA",
            "data:text/plain;base64,AAAA", "anything,AAAA", "data:image/png;base64,aGVsbG8="
        ]
        for url in urls {
            // When
            XCTAssertThrowsError(try GeneratedImageDecoder.decode(dataURL: url)) { error in
                // Then
                XCTAssertEqual(error as? APIError, .invalidResponse)
            }
        }
    }

    func test_decode_imageAtByteLimit_acceptsWithoutResizing() throws {
        // Given
        var data = try XCTUnwrap(Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"))
        data.append(Data(repeating: 0, count: 25 * 1_024 * 1_024 - data.count))

        // When
        let decoded = try GeneratedImageDecoder.decode(dataURL: "data:image/gif;base64,\(data.base64EncodedString())")

        // Then
        XCTAssertEqual(decoded.data, data)
        XCTAssertEqual(decoded.mimeType, "image/gif")
    }

    func test_decode_overByteLimit_rejectsEvenWhenBase64HasSameEncodedLengthAsLimit() {
        // Given
        let data = Data(repeating: 0, count: 25 * 1_024 * 1_024 + 1)
        let url = "data:image/png;base64,\(data.base64EncodedString())"

        // When
        XCTAssertThrowsError(try GeneratedImageDecoder.decode(dataURL: url)) { error in
            // Then
            XCTAssertEqual(error as? APIError, .invalidResponse)
        }
        XCTAssertThrowsError(try GeneratedImageDecoder.decode(data: data)) { error in
            XCTAssertEqual(error as? APIError, .invalidResponse)
        }
    }
}
