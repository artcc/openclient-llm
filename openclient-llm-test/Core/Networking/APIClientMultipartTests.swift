//
//  APIClientMultipartTests.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 09/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class APIClientMultipartTests: XCTestCase {
    func test_multipartRequest_multipleFiles_sendsOrderedBinaryPartsAndCustomTimeout() async throws {
        // Given
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let sut = APIClient(session: session, serverBaseURL: "https://example.invalid/proxy/v1", apiKey: "test-token")
        let firstData = Data([0x00, 0xFF, 0x0D, 0x0A, 0x80])
        let secondData = Data([0xFE, 0x00, 0x81, 0x0A])
        let files = [
            MultipartFileData(field: "image[]", data: firstData, fileName: "first.png", mimeType: "image/png"),
            MultipartFileData(field: "image[]", data: secondData, fileName: "second.jpg", mimeType: "image/jpeg")
        ]

        // When
        let captured: MockMultipartURLProtocol.CapturedRequest = try await sut.multipartRequest(
            endpoint: "images/edits",
            fields: ["prompt": "Combine both images"],
            files: files,
            timeoutInterval: 600
        )

        // Then
        XCTAssertEqual(captured.method, "POST")
        XCTAssertEqual(captured.url.absoluteString, "https://example.invalid/proxy/v1/images/edits")
        XCTAssertEqual(captured.authorization, "Bearer test-token")
        XCTAssertEqual(captured.timeoutInterval, 600)
        let boundary = try multipartBoundary(from: captured)
        var expected = Data("--\(boundary)\r\n".utf8)
        expected.append(Data("Content-Disposition: form-data; name=\"prompt\"\r\n\r\nCombine both images\r\n".utf8))
        expected.append(Data("--\(boundary)\r\n".utf8))
        expected.append(Data("Content-Disposition: form-data; name=\"image[]\"; filename=\"first.png\"\r\n".utf8))
        expected.append(Data("Content-Type: image/png\r\n\r\n".utf8))
        expected.append(firstData)
        expected.append(Data("\r\n--\(boundary)\r\n".utf8))
        expected.append(Data("Content-Disposition: form-data; name=\"image[]\"; filename=\"second.jpg\"\r\n".utf8))
        expected.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        expected.append(secondData)
        expected.append(Data("\r\n--\(boundary)--\r\n".utf8))
        XCTAssertEqual(captured.body, expected)
    }

    func test_multipartRequest_singleAudioFile_preservesBodyAndDefaultTimeout() async throws {
        // Given
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let sut: any APIClientProtocol = APIClient(
            session: session, serverBaseURL: "https://example.invalid/proxy", apiKey: ""
        )
        let audioData = Data([0x00, 0xFF, 0x80, 0x01])
        let file = MultipartFileData(field: "file", data: audioData, fileName: "audio.m4a", mimeType: "audio/m4a")

        // When
        let captured: MockMultipartURLProtocol.CapturedRequest = try await sut.multipartRequest(
            endpoint: "v1/audio/transcriptions",
            fields: ["model": "whisper"],
            file: file
        )

        // Then
        XCTAssertEqual(captured.method, "POST")
        XCTAssertEqual(captured.url.absoluteString, "https://example.invalid/proxy/v1/audio/transcriptions")
        XCTAssertNil(captured.authorization)
        XCTAssertEqual(captured.timeoutInterval, 125)
        let boundary = try multipartBoundary(from: captured)
        var expected = Data("--\(boundary)\r\n".utf8)
        expected.append(Data("Content-Disposition: form-data; name=\"model\"\r\n\r\nwhisper\r\n".utf8))
        expected.append(Data("--\(boundary)\r\n".utf8))
        expected.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".utf8))
        expected.append(Data("Content-Type: audio/m4a\r\n\r\n".utf8))
        expected.append(audioData)
        expected.append(Data("\r\n--\(boundary)--\r\n".utf8))
        XCTAssertEqual(captured.body, expected)
    }

    func test_multipartRequest_mockMultipleFiles_capturesArgumentsAndReturnsResult() async throws {
        // Given
        let sut = MockAPIClient()
        sut.multipartResult = "edited"
        let files = [
            MultipartFileData(field: "image[]", data: Data([0xFF]), fileName: "first.png", mimeType: "image/png"),
            MultipartFileData(field: "image[]", data: Data([0x80]), fileName: "second.jpg", mimeType: "image/jpeg")
        ]
        let fields = ["model": "image-model", "prompt": "Combine both images"]

        // When
        let result: String = try await sut.multipartRequest(
            endpoint: "images/edits", fields: fields, files: files, timeoutInterval: 600
        )

        // Then
        XCTAssertEqual(result, "edited")
        XCTAssertEqual(sut.lastMultipartEndpoint, "images/edits")
        XCTAssertEqual(sut.lastMultipartFields, fields)
        XCTAssertEqual(sut.lastMultipartFiles?.map(\.field), files.map(\.field))
        XCTAssertEqual(sut.lastMultipartFiles?.map(\.fileName), files.map(\.fileName))
        XCTAssertEqual(sut.lastMultipartFiles?.map(\.mimeType), files.map(\.mimeType))
        XCTAssertEqual(sut.lastMultipartFiles?.map(\.data), files.map(\.data))
        XCTAssertEqual(sut.lastMultipartTimeoutInterval, 600)
    }

    func test_multipartRequest_mockSingleFileWithError_capturesDelegationAndThrowsConfiguredError() async throws {
        // Given
        let sut = MockAPIClient()
        sut.multipartResult = "ignored"
        sut.multipartError = APIError.unauthorized
        let file = MultipartFileData(field: "file", data: Data([0xFF]), fileName: "audio.m4a", mimeType: "audio/m4a")

        // When
        do {
            let _: String = try await sut.multipartRequest(
                endpoint: "v1/audio/transcriptions", fields: ["model": "whisper"], file: file
            )
            XCTFail("Expected the configured multipart error")
        } catch {
            // Then
            guard case APIError.unauthorized = error else {
                return XCTFail("Expected unauthorized, got \(error)")
            }
        }
        XCTAssertEqual(sut.lastMultipartEndpoint, "v1/audio/transcriptions")
        XCTAssertEqual(sut.lastMultipartFields, ["model": "whisper"])
        XCTAssertEqual(sut.lastMultipartFiles?.map(\.data), [file.data])
        XCTAssertEqual(sut.lastMultipartFiles?.map(\.field), [file.field])
        XCTAssertEqual(sut.lastMultipartFiles?.map(\.fileName), [file.fileName])
        XCTAssertEqual(sut.lastMultipartFiles?.map(\.mimeType), [file.mimeType])
        XCTAssertEqual(sut.lastMultipartTimeoutInterval, 125)
    }

    // MARK: - Private

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockMultipartURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func multipartBoundary(from captured: MockMultipartURLProtocol.CapturedRequest) throws -> String {
        let contentType = try XCTUnwrap(captured.contentType)
        let prefix = "multipart/form-data; boundary="
        XCTAssertTrue(contentType.hasPrefix(prefix))
        let boundary = String(contentType.dropFirst(prefix.count))
        XCTAssertFalse(boundary.isEmpty)
        return boundary
    }
}
