//
//  APIClientStreamingTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 01/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class APIClientStreamingTests: XCTestCase {
    func test_streamRequest_multilineEvents_preservesDataAcrossSupportedLineEndings() async throws {
        for endpoint in ["lf", "crlf", "cr"] {
            // Given
            let session = makeSession()
            defer { session.invalidateAndCancel() }
            let client = APIClient(session: session, serverBaseURL: "https://example.invalid", apiKey: "")

            // When
            var payloads: [String] = []
            for try await data in client.streamRequest(endpoint: endpoint, body: ["stream": true]) {
                payloads.append(try XCTUnwrap(String(bytes: data, encoding: .utf8)))
            }

            // Then: fields and comments are ignored, only one optional space is removed, and DONE stops delivery.
            XCTAssertEqual(payloads, ["{\"text\":\n\"á🙂\"}", " leading space"])
        }
    }

    func test_streamRequest_unterminatedEvent_doesNotDeliverPartialPayload() async throws {
        // Given
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let client = APIClient(session: session, serverBaseURL: "https://example.invalid", apiKey: "")

        // When
        var payloads: [String] = []
        for try await data in client.streamRequest(endpoint: "unterminated", body: ["stream": true]) {
            payloads.append(try XCTUnwrap(String(bytes: data, encoding: .utf8)))
        }

        // Then
        XCTAssertEqual(payloads, ["complete"])
    }

    func test_streamAgentCompletion_mixedDataPrefixes_preservesToolArguments() async throws {
        // Given
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let repository = ChatRepository(
            apiClient: APIClient(session: session, serverBaseURL: "https://example.invalid/tools", apiKey: ""),
            attachmentRepository: MockAttachmentRepository()
        )

        // When
        var responses: [ChatCompletionResponse] = []
        for try await event in repository.streamAgentCompletion(
            messages: [], model: "test", parameters: .default, tools: nil
        ) {
            if case .completed(let response) = event { responses.append(response) }
        }

        // Then: losing the unspaced middle event would silently turn 10 into 1.
        XCTAssertEqual(responses.count, 1)
        let call = try XCTUnwrap(responses.first?.choices.first?.message.toolCalls?.first)
        XCTAssertEqual(call.id, "call")
        XCTAssertEqual(call.function.name, "lookup")
        XCTAssertEqual(call.function.arguments, "{\"amount\":10}")
        XCTAssertEqual(responses.first?.choices.first?.finishReason, "tool_calls")
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SSEFixtureURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class SSEFixtureURLProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool { true }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let payload = Self.payload(for: url.path),
              let response = HTTPURLResponse(
                  url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "text/event-stream"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // Include byte boundaries inside UTF-8 characters, CRLF pairs, and data field names.
        for byte in payload.utf8 {
            client?.urlProtocol(self, didLoad: Data([byte]))
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func payload(for path: String) -> String? {
        switch path {
        case "/lf", "/crlf", "/cr":
            let lineEnding = path == "/crlf" ? "\r\n" : path == "/cr" ? "\r" : "\n"
            return [
                "\u{FEFF}: keepalive", "event: message", "data: {\"text\":", "id: ignored", "data:\"á🙂\"}",
                "", "data:  leading space", "", "data:[DONE]", "", "data: must not be delivered", "", ""
            ].joined(separator: lineEnding)
        case "/unterminated":
            return "data: complete\n\ndata: incomplete\n"
        case "/tools/chat/completions":
            let first = #"{"index":0,"id":"call","type":"function","function":{"name":"lookup","#
                + #""arguments":"{\"amount\":1"}}"#
            let middle = #"{"index":0,"function":{"arguments":"0"}}"#
            let last = #"{"index":0,"function":{"arguments":"}"}}"#
            return toolEvent(first, prefix: "data: ")
                + toolEvent(middle, prefix: "data:")
                + toolEvent(last, prefix: "data: ", finish: "tool_calls")
                + "data:[DONE]\n\n"
        default:
            return nil
        }
    }

    private static func toolEvent(_ call: String, prefix: String, finish: String? = nil) -> String {
        let reason = finish.map { "\"\($0)\"" } ?? "null"
        return "\(prefix){\"id\":\"stream\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[\(call)]},"
            + "\"finish_reason\":\(reason)}]}\n\n"
    }
}
