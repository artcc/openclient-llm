//
//  APIClientTimeoutTests.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class APIClientTimeoutTests: XCTestCase {
    func test_streamRequest_capturedConfigurationDefault_uses60Seconds() async throws {
        // Given
        let session = makeStreamSession()
        defer { session.invalidateAndCancel() }
        let sut = APIClient(session: session, serverBaseURL: "https://example.invalid", apiKey: "")

        // When
        let timeout = try await capturedStreamTimeout(sut)

        // Then
        XCTAssertEqual(timeout, 60)
    }

    func test_streamRequest_capturedConfigurationCustomTimeout_uses600Seconds() async throws {
        // Given
        let session = makeStreamSession()
        defer { session.invalidateAndCancel() }
        let sut = APIClient(
            session: session, serverBaseURL: "https://example.invalid", apiKey: "", streamTimeoutInterval: 600
        )

        // When
        let timeout = try await capturedStreamTimeout(sut)

        // Then
        XCTAssertEqual(timeout, 600)
    }

    func test_streamRequest_settingsConfigurationDefault_uses60Seconds() async throws {
        // Given
        let session = makeStreamSession()
        defer { session.invalidateAndCancel() }
        let settings = MockSettingsManager()
        settings.serverBaseURL = "https://example.invalid"
        let sut = APIClient(session: session, settingsManager: settings)

        // When
        let timeout = try await capturedStreamTimeout(sut)

        // Then
        XCTAssertEqual(timeout, 60)
    }

    func test_streamRequest_settingsConfigurationCustomTimeout_uses600Seconds() async throws {
        // Given
        let session = makeStreamSession()
        defer { session.invalidateAndCancel() }
        let settings = MockSettingsManager()
        settings.serverBaseURL = "https://example.invalid"
        let sut = APIClient(session: session, settingsManager: settings, streamTimeoutInterval: 600)

        // When
        let timeout = try await capturedStreamTimeout(sut)

        // Then
        XCTAssertEqual(timeout, 600)
    }

    func test_request_customStreamTimeout_preservesDefaultRequestTimeout() async throws {
        // Given
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockMultipartURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let sut: any APIClientProtocol = APIClient(
            session: session, serverBaseURL: "https://example.invalid", apiKey: "", streamTimeoutInterval: 600
        )

        // When
        let captured: MockMultipartURLProtocol.CapturedRequest = try await sut.request(
            endpoint: "chat/completions", method: .post, body: ["model": "chat-model"]
        )

        // Then
        XCTAssertEqual(captured.timeoutInterval, 60)
    }

    // MARK: - Private

    private func makeStreamSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamTimeoutURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func capturedStreamTimeout(_ client: any APIClientProtocol) async throws -> TimeInterval {
        var timeouts: [TimeInterval] = []
        for try await data in client.streamRequest(endpoint: "chat/completions", body: ["model": "image-model"]) {
            timeouts.append(try JSONDecoder().decode(TimeInterval.self, from: data))
        }
        XCTAssertEqual(timeouts.count, 1)
        return try XCTUnwrap(timeouts.first)
    }
}

private final class StreamTimeoutURLProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool { true }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 200,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "text/event-stream"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        // Echo the timeout through SSE without shared mutable callback state.
        let data = Data("data: \(request.timeoutInterval)\n\ndata: [DONE]\n\n".utf8)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
