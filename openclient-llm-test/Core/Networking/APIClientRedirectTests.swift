//
//  APIClientRedirectTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 02/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class APIClientRedirectTests: XCTestCase {
    func test_requests_withoutCustomHeaders_followCrossOriginRedirects() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        for transport in Transport.allCases {
            let succeeded = try await perform(transport, session: session, route: "cross", headers: [])
            XCTAssertTrue(succeeded, "Expected redirect support for \(transport)")
        }
    }

    func test_requests_withCustomHeaders_rejectCrossOriginRedirects() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        for transport in Transport.allCases {
            do {
                let succeeded = try await perform(
                    transport, session: session, route: "cross", headers: [.init(name: "X-Test", value: "test-value")]
                )
                XCTAssertEqual(transport, .health)
                XCTAssertFalse(succeeded)
            } catch {
                if transport == .connection {
                    XCTAssertTrue(error is OnboardingRepositoryError)
                } else {
                    XCTAssertEqual(error as? APIError, .httpError(statusCode: 307))
                }
            }
        }
    }

    func test_requests_withCustomHeaders_followSameOriginRedirects() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        for transport in Transport.allCases {
            let succeeded = try await perform(
                transport, session: session, route: "same", headers: [.init(name: "X-Test", value: "test-value")]
            )
            XCTAssertTrue(succeeded, "Expected same-origin redirect support for \(transport)")
        }
    }

    func test_requests_automaticChatID_rejectsCrossOriginAndPreservesSameOriginHeaders() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let chatID = UUID()
        for transport in [Transport.json, .raw, .multipart, .stream] {
            do {
                _ = try await perform(transport, session: session, route: "cross", headers: [], chatID: chatID)
                XCTFail("Expected cross-origin redirect rejection for \(transport)")
            } catch {
                XCTAssertEqual(error as? APIError, .httpError(statusCode: 307))
            }
            let sameOrigin = try await perform(
                transport, session: session, route: "same", headers: [], chatID: chatID
            )
            XCTAssertTrue(sameOrigin)
        }
    }

    private enum Transport: CaseIterable {
        case json, raw, multipart, stream, connection, health
    }

    private func perform(
        _ transport: Transport, session: URLSession, route: String, headers: [ServerHTTPHeader], chatID: UUID? = nil
    ) async throws -> Bool {
        let baseURL = "https://source.invalid/\(route)"
        let client = APIClient(
            session: session, serverBaseURL: baseURL, apiKey: "", customHeaders: headers,
            chatIDHeaderName: "X-Chat-ID", chatID: chatID
        )
        let onboarding = OnboardingRepository(session: session)
        switch transport {
        case .json:
            let result: [String: String] = try await client.request(endpoint: "capture", method: .get, body: nil)
            return result["result"] == "ok"
        case .raw:
            let result = try await client.rawDataRequest(endpoint: "capture", body: ["input": "test"])
            return try JSONDecoder().decode([String: String].self, from: result)["result"] == "ok"
        case .multipart:
            let result: [String: String] = try await client.multipartRequest(
                endpoint: "capture", fields: [:], files: [], timeoutInterval: 5
            )
            return result["result"] == "ok"
        case .stream:
            var count = 0
            for try await data in client.streamRequest(endpoint: "stream", body: ["stream": true]) {
                XCTAssertEqual(try JSONDecoder().decode([String: String].self, from: data)["result"], "ok")
                count += 1
            }
            return count == 1
        case .connection:
            try await onboarding.testConnection(serverURL: baseURL, apiKey: "", customHeaders: headers)
            return true
        case .health:
            return await onboarding.checkLiteLLMHealth(serverURL: baseURL, customHeaders: headers)
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectFixtureURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class RedirectFixtureURLProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        if !url.path.hasPrefix("/final/") {
            let host = url.path.hasPrefix("/cross/") ? "destination.invalid" : "source.invalid"
            guard let destination = URL(string: "https://\(host)/final\(url.path)"),
                  let response = HTTPURLResponse(
                      url: url, statusCode: 307, httpVersion: "HTTP/1.1",
                      headerFields: ["Location": destination.absoluteString]
                  ) else { return }
            var redirected = request
            redirected.url = destination
            client?.urlProtocol(self, wasRedirectedTo: redirected, redirectResponse: response)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let requiresHeader = url.path.hasPrefix("/final/same/")
        let hasHeader = request.value(forHTTPHeaderField: "X-Test") == "test-value"
            || request.value(forHTTPHeaderField: "X-Chat-ID").flatMap(UUID.init(uuidString:)) != nil
        let status = requiresHeader && !hasHeader ? 401 : 200
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
            return
        }
        let json = #"{"result":"ok","litellm_version":"test"}"#
        let body = url.lastPathComponent == "stream" ? "data: \(json)\n\ndata: [DONE]\n\n" : json
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
