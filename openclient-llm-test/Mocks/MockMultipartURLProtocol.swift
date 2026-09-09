//
//  MockMultipartURLProtocol.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 09/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

final class MockMultipartURLProtocol: URLProtocol {
    struct CapturedRequest: Codable, Sendable {
        let url: URL
        let method: String?
        let contentType: String?
        let authorization: String?
        let timeoutInterval: TimeInterval
        let body: Data
    }

    override static func canInit(with request: URLRequest) -> Bool { true }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let url = request.url,
                  let response = HTTPURLResponse(
                      url: url,
                      statusCode: 200,
                      httpVersion: "HTTP/1.1",
                      headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLError(.badURL)
            }
            // Echo the captured request instead of sharing mutable state across URLSession callbacks and tests.
            let captured = CapturedRequest(
                url: url,
                method: request.httpMethod,
                contentType: request.value(forHTTPHeaderField: "Content-Type"),
                authorization: request.value(forHTTPHeaderField: "Authorization"),
                timeoutInterval: request.timeoutInterval,
                body: try readBody()
            )
            let data = try JSONEncoder().encode(captured)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    // MARK: - Private

    private func readBody() throws -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }

        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            guard count > 0 else { return body }
            body.append(contentsOf: buffer.prefix(count))
        }
    }
}
