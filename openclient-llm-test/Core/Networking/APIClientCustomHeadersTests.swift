//
//  APIClientCustomHeadersTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 02/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class APIClientCustomHeadersTests: XCTestCase {
    func test_requests_capturedConfiguration_sendsHeadersAcrossTransports() async throws {
        // Given
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let sut = APIClient(
            session: session, serverBaseURL: "https://example.invalid/v1", apiKey: "test-key",
            customHeaders: headers
        )

        // When
        let regular: CapturedHeaders = try await sut.request(endpoint: "capture", method: .get, body: nil)
        let multipart: CapturedHeaders = try await sut.multipartRequest(
            endpoint: "capture", fields: [:], files: [], timeoutInterval: 30
        )
        let raw = try await sut.rawDataRequest(endpoint: "capture", body: ["input": "test"])
        var streamed: [CapturedHeaders] = []
        for try await data in sut.streamRequest(endpoint: "stream", body: ["stream": true]) {
            streamed.append(try JSONDecoder().decode(CapturedHeaders.self, from: data))
        }

        // Then
        XCTAssertEqual(streamed.count, 1)
        for captured in [regular, multipart, try JSONDecoder().decode(CapturedHeaders.self, from: raw)] + streamed {
            XCTAssertEqual(captured.session, "test-session")
            XCTAssertEqual(captured.userAgent, "OpenClient-Test")
            XCTAssertEqual(captured.authorization, "Bearer test-key")
        }
        XCTAssertTrue(multipart.contentType?.hasPrefix("multipart/form-data; boundary=") == true)
        XCTAssertEqual(streamed.first?.contentType, "application/json")
    }

    func test_request_settingsChange_readsHeadersForEachNewRequest() async throws {
        // Given
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let settings = MockSettingsManager()
        settings.serverBaseURL = "https://example.invalid"
        settings.customHeaders = headers
        let sut = APIClient(session: session, settingsManager: settings)

        // When
        let first: CapturedHeaders = try await sut.request(endpoint: "capture", method: .get, body: nil)
        settings.customHeaders = []
        let second: CapturedHeaders = try await sut.request(endpoint: "capture", method: .get, body: nil)

        // Then
        XCTAssertEqual(first.session, "test-session")
        XCTAssertNil(second.session)
    }

    func test_downloadData_externalDestination_omitsServerHeadersAndCredentials() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let sut = APIClient(
            session: session, serverBaseURL: "https://example.invalid", apiKey: "test-key", customHeaders: headers,
            chatIDHeaderName: "X-Chat-ID", chatID: UUID()
        )
        let result = try await sut.downloadData(from: XCTUnwrap(URL(string: "https://external.invalid/capture")))
        let captured = try JSONDecoder().decode(CapturedHeaders.self, from: result.data)
        XCTAssertNil(captured.session)
        XCTAssertNil(captured.authorization)
        XCTAssertNil(captured.chatId)
        XCTAssertNotEqual(captured.userAgent, "OpenClient-Test")
    }

    func test_connectionAndHealth_customHeadersRequired_usesSuppliedDraftHeaders() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let sut = OnboardingRepository(session: session)
        try await sut.testConnection(serverURL: "https://example.invalid", apiKey: "", customHeaders: headers)
        let healthy = await sut.checkLiteLLMHealth(serverURL: "https://example.invalid", customHeaders: headers)
        let withoutHeaders = await sut.checkLiteLLMHealth(serverURL: "https://example.invalid")
        XCTAssertTrue(healthy)
        XCTAssertFalse(withoutHeaders)
    }

    func test_request_invalidPersistedHeaders_rejectsBeforeTransport() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let sut = APIClient(
            session: session, serverBaseURL: "https://example.invalid", apiKey: "",
            customHeaders: [.init(name: "X-Test", value: "test\r\nInjected: yes")]
        )
        do {
            let _: CapturedHeaders = try await sut.request(endpoint: "capture", method: .get, body: nil)
            XCTFail("Expected invalid request")
        } catch {
            guard case APIError.invalidRequest = error else { return XCTFail("Expected invalid request") }
        }
    }

    func test_redirect_originChanges_rejectsForwardingServerRequest() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let source = try XCTUnwrap(URL(string: "https://example.invalid/v1"))
        let task = session.dataTask(with: source)
        defer { task.cancel() }
        let response = try XCTUnwrap(HTTPURLResponse(url: source, statusCode: 302, httpVersion: nil, headerFields: nil))
        let destinations = [
            ("https://EXAMPLE.invalid:443/v2", true),
            ("https://other.invalid/v2", false),
            ("http://example.invalid/v2", false),
            ("https://example.invalid:8443/v2", false)
        ]
        for (destination, allowed) in destinations {
            var request = URLRequest(url: try XCTUnwrap(URL(string: destination)))
            request.setValue("test-session", forHTTPHeaderField: "x-opencode-session")
            let forwarded = await withCheckedContinuation { continuation in
                ServerRequestRedirectDelegate.shared.urlSession(
                    session, task: task, willPerformHTTPRedirection: response, newRequest: request
                ) { continuation.resume(returning: $0) }
            }
            XCTAssertEqual(forwarded != nil, allowed)
            if allowed { XCTAssertEqual(forwarded?.value(forHTTPHeaderField: "x-opencode-session"), "test-session") }
        }
    }

    func test_requests_automaticChatID_sendsSameIDAcrossAllTransports() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let chatID = UUID()
        let sut = APIClient(
            session: session, serverBaseURL: "https://example.invalid", apiKey: "test-key", customHeaders: headers,
            chatIDHeaderName: "X-Chat-ID", chatID: chatID
        )

        let regular: CapturedHeaders = try await sut.request(endpoint: "capture", method: .post, body: nil)
        let multipart: CapturedHeaders = try await sut.multipartRequest(
            endpoint: "capture", fields: [:], files: [], timeoutInterval: 30
        )
        let raw = try await sut.rawDataRequest(endpoint: "capture", body: ["input": "test"])
        var captured = [regular, multipart, try JSONDecoder().decode(CapturedHeaders.self, from: raw)]
        for try await data in sut.streamRequest(endpoint: "stream", body: ["stream": true]) {
            captured.append(try JSONDecoder().decode(CapturedHeaders.self, from: data))
        }

        XCTAssertEqual(captured.count, 4)
        for request in captured {
            XCTAssertEqual(request.chatId, chatID.uuidString)
            XCTAssertEqual(request.session, "test-session")
            XCTAssertEqual(request.authorization, "Bearer test-key")
        }
    }

    func test_request_chatContexts_areIndependentAndOmittedWhenDisabledOrAbsent() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let firstID = UUID()
        let secondID = UUID()
        let contexts: [(String?, UUID?)] = [
            ("X-Chat-ID", firstID), ("X-Chat-ID", secondID), ("X-Chat-ID", nil), (nil, firstID)
        ]
        let clients = contexts.map { name, chatID in
            APIClient(
                session: session, serverBaseURL: "https://example.invalid", apiKey: "",
                chatIDHeaderName: name, chatID: chatID
            )
        }
        for index in [0, 1, 2, 3, 0] {
            let captured: CapturedHeaders = try await clients[index].request(
                endpoint: "capture", method: .get, body: nil
            )
            let expected = contexts[index].0 == nil ? nil : contexts[index].1?.uuidString
            XCTAssertEqual(captured.chatId, expected)
        }
    }

    func test_request_discoveryClient_omitsConfiguredChatIDHeader() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let settings = MockSettingsManager()
        settings.serverBaseURL = "https://example.invalid/v1"
        settings.chatIDHeaderName = "X-Chat-ID"
        let sut = APIClient(session: session, settingsManager: settings)
        for endpoint in ["models", "model/info", "v1/search/tools", "v1/mcp/server", "mcp-rest/tools/list"] {
            let captured: CapturedHeaders = try await sut.request(endpoint: endpoint, method: .get, body: nil)
            XCTAssertNil(captured.chatId)
        }
    }

    private var headers: [ServerHTTPHeader] {
        [.init(name: "x-opencode-session", value: "test-session"), .init(name: "User-Agent", value: "OpenClient-Test")]
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HeaderEchoURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

nonisolated private struct CapturedHeaders: Codable, Sendable {
    let session: String?
    let userAgent: String?
    let authorization: String?
    let contentType: String?
    let chatId: String?
}

private final class HeaderEchoURLProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let captured = CapturedHeaders(
            session: request.value(forHTTPHeaderField: "x-opencode-session"),
            userAgent: request.value(forHTTPHeaderField: "User-Agent"),
            authorization: request.value(forHTTPHeaderField: "Authorization"),
            contentType: request.value(forHTTPHeaderField: "Content-Type"),
            chatId: request.value(forHTTPHeaderField: "X-Chat-ID")
        )
        do {
            var data = try JSONEncoder().encode(captured)
            var status = 200
            if ["/models", "/health/readiness"].contains(url.path) {
                status = captured.session == "test-session" && captured.chatId == nil ? 200 : 401
                data = Data(#"{"litellm_version":"test"}"#.utf8)
            } else if url.lastPathComponent == "stream" {
                guard let json = String(data: data, encoding: .utf8) else { throw URLError(.cannotDecodeContentData) }
                data = Data("data: \(json)\n\ndata: [DONE]\n\n".utf8)
            }
            guard let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: nil, headerFields: nil
            ) else {
                throw URLError(.badServerResponse)
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
