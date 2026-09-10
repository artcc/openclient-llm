//
//  ImageFileDocumentTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 09/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import openclient_llm

@MainActor
final class ImageFileDocumentTests: XCTestCase {
    func test_init_pngAndJPEG_preservesBytesAndDetectsActualFormat() throws {
        // Given
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 24)).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        }
        let examples: [(Data, UTType)] = [
            (try XCTUnwrap(image.pngData()), .png),
            (try XCTUnwrap(image.jpegData(compressionQuality: 0.9)), .jpeg)
        ]

        for (data, type) in examples {
            // When
            let document = try ImageFileDocument(data: data)

            // Then
            XCTAssertEqual(document.data, data)
            XCTAssertEqual(document.contentType, type)
            XCTAssertEqual(document.contentType.preferredFilenameExtension, type.preferredFilenameExtension)
            XCTAssertTrue(ImageFileDocument.writableContentTypes.contains(type))
        }
    }

    func test_init_gif_preservesOriginalFormatWithoutConversion() throws {
        // Given
        let data = try XCTUnwrap(Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"))

        // When
        let document = try ImageFileDocument(data: data)

        // Then
        XCTAssertEqual(document.data, data)
        XCTAssertEqual(document.contentType, .gif)
        XCTAssertTrue(ImageFileDocument.writableContentTypes.contains(.gif))
    }

    func test_init_invalidImage_rejectsExport() {
        for data in [Data(), Data("not an image".utf8)] {
            // Given / When / Then
            XCTAssertThrowsError(try ImageFileDocument(data: data)) { error in
                XCTAssertEqual((error as? CocoaError)?.code, .fileReadCorruptFile)
            }
        }
    }
}
