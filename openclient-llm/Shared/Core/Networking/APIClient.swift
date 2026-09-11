//
//  APIClient.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

struct APIClient: APIClientProtocol, Sendable {
    // MARK: - Properties

    private let session: URLSession
    private let serverBaseURLProvider: @MainActor @Sendable () -> String
    private let apiKeyProvider: @MainActor @Sendable () -> String
    private let streamTimeoutInterval: TimeInterval

    // MARK: - Init

    init(
        session: URLSession = .shared,
        settingsManager: SettingsManagerProtocol = SettingsManager(),
        streamTimeoutInterval: TimeInterval = 60
    ) {
        self.session = session
        self.serverBaseURLProvider = { settingsManager.getServerBaseURL() }
        self.apiKeyProvider = { settingsManager.getAPIKey() }
        self.streamTimeoutInterval = streamTimeoutInterval
    }

    init(
        session: URLSession = .shared,
        serverBaseURL: String,
        apiKey: String,
        streamTimeoutInterval: TimeInterval = 60
    ) {
        self.session = session
        self.serverBaseURLProvider = { serverBaseURL }
        self.apiKeyProvider = { apiKey }
        self.streamTimeoutInterval = streamTimeoutInterval
    }

    // MARK: - Public

    func request<T: Decodable & Sendable>(
        endpoint: String,
        method: HTTPMethod,
        body: (any Encodable & Sendable)?,
        timeoutInterval: TimeInterval
    ) async throws -> T {
        let urlRequest = try buildRequest(
            endpoint: endpoint,
            method: method,
            body: body,
            timeoutInterval: timeoutInterval
        )
        LogManager.network("→ \(method.rawValue) /\(endpoint)")

        do {
            let (data, response) = try await performRequest(urlRequest)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                LogManager.error("HTTP \(http.statusCode) /\(endpoint) (\(data.count) bytes)")
            }
            try validateResponse(response)

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            LogManager.network("← \(method.rawValue) /\(endpoint) [\(statusCode)] \(data.count) bytes")

            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                return try decoder.decode(T.self, from: data)
            } catch {
                LogManager.error("Decoding failed for /\(endpoint): \(error)")
                throw APIError.decodingError
            }
        } catch let error as APIError {
            LogManager.error("Request failed /\(endpoint): \(error.localizedDescription)")
            throw error
        }
    }

    func streamRequest(
        endpoint: String,
        body: any Encodable & Sendable
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try buildRequest(
                        endpoint: endpoint,
                        method: .post,
                        body: body,
                        timeoutInterval: streamTimeoutInterval
                    )
                    LogManager.network("→ STREAM POST /\(endpoint)")

                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    try validateResponse(response)
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    LogManager.network("← STREAM /\(endpoint) [\(statusCode)] opened")

                    var chunkCount = 0
                    for try await line in bytes.lines {
                        guard !Task.isCancelled else {
                            LogManager.debug("Stream cancelled /\(endpoint) after \(chunkCount) chunks")
                            break
                        }

                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))

                        if payload.trimmingCharacters(in: .whitespaces) == "[DONE]" {
                            LogManager.network("← STREAM /\(endpoint) [DONE] — \(chunkCount) chunks received")
                            break
                        }

                        if let data = payload.data(using: .utf8) {
                            chunkCount += 1
                            continuation.yield(data)
                        }
                    }
                    continuation.finish()
                } catch {
                    let mapped = mapError(error)
                    LogManager.error("Stream error /\(endpoint): \(mapped.localizedDescription)")
                    continuation.finish(throwing: mapped)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func multipartRequest<T: Decodable & Sendable>(
        endpoint: String,
        fields: [String: String],
        files: [MultipartFileData],
        timeoutInterval: TimeInterval
    ) async throws -> T {
        LogManager.network("→ MULTIPART POST /\(endpoint) files=\(files.count)")
        var request = try buildRequest(
            endpoint: endpoint,
            method: .post,
            body: nil,
            timeoutInterval: timeoutInterval
        )
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        for (key, value) in fields {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }

        for file in files {
            body.append(Data("--\(boundary)\r\n".utf8))
            let disposition = "Content-Disposition: form-data; name=\"\(file.field)\"; "
                + "filename=\"\(file.fileName)\"\r\n"
            body.append(Data(disposition.utf8))
            body.append(Data("Content-Type: \(file.mimeType)\r\n\r\n".utf8))
            body.append(file.data)
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))

        request.httpBody = body

        do {
            let (data, response) = try await performRequest(request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                LogManager.error("HTTP \(http.statusCode) /\(endpoint) (\(data.count) bytes)")
            }
            try validateResponse(response)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            LogManager.network("← MULTIPART /\(endpoint) [\(statusCode)] \(data.count) bytes")

            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                return try decoder.decode(T.self, from: data)
            } catch {
                LogManager.error("Decoding failed for multipart /\(endpoint): \(error)")
                throw APIError.decodingError
            }
        } catch let error as APIError {
            LogManager.error("Multipart request failed /\(endpoint): \(error.localizedDescription)")
            throw error
        }
    }

    func searchRequest(
        toolName: String,
        body: LiteLLMSearchRequest
    ) async throws -> LiteLLMSearchResponse {
        let endpoint = "v1/search/\(toolName)"
        return try await request(endpoint: endpoint, method: .post, body: body)
    }

    func fetchSearchTools() async throws -> SearchToolsResponse {
        try await request(endpoint: "v1/search/tools", method: .get, body: nil)
    }

    func listMCPServers() async throws -> [MCPServerInfo] {
        LogManager.network("→ GET /v1/mcp/server")
        let response: MCPServersResponse = try await request(
            endpoint: "v1/mcp/server",
            method: .get,
            body: nil
        )
        LogManager.success("listMCPServers returned \(response.data.count) servers")
        return response.data
    }

    func listMCPTools(serverId: String) async throws -> [MCPToolInfo] {
        LogManager.network("→ GET /mcp-rest/tools/list server_id=\(serverId)")
        let response: MCPToolsResponse = try await request(
            endpoint: "mcp-rest/tools/list",
            method: .get,
            body: nil,
            queryItems: [URLQueryItem(name: "server_id", value: serverId)]
        )
        let tools = response.data.map { tool in
            MCPToolInfo(
                name: tool.name,
                description: tool.description,
                serverId: serverId,
                serverName: serverId,
                inputSchema: tool.inputSchema,
                rawInputSchemaData: tool.rawInputSchemaData,
                isInputSchemaSupported: tool.isInputSchemaSupported
            )
        }
        LogManager.success("listMCPTools server=\(serverId) tools=\(tools.count)")
        return tools
    }

    func callMCPTool(serverId: String, toolName: String, arguments: String) async throws -> String {
        LogManager.network("→ POST /mcp-rest/tools/call server=\(serverId) tool=\(toolName)")
        let parsedArguments = try parseArgumentsJSON(arguments)
        let body = MCPCallRequest(serverId: serverId, name: toolName, arguments: parsedArguments)
        let response: MCPCallResponse = try await request(
            endpoint: "mcp-rest/tools/call",
            method: .post,
            body: body
        )
        guard let content = response.content, !content.isEmpty else {
            throw APIError.invalidResponse
        }
        let text = String(content.compactMap(\.text).joined(separator: "\n").prefix(100_000))
        if response.isError == true {
            throw APIError.toolExecutionFailed(String(localized: "The MCP server reported a tool error."))
        }
        LogManager.success("callMCPTool \(toolName) result=\(text.count) chars isError=\(response.isError ?? false)")
        return text
    }

    func rawDataRequest(
        endpoint: String,
        body: any Encodable & Sendable
    ) async throws -> Data {
        let urlRequest = try buildRequest(endpoint: endpoint, method: .post, body: body)
        LogManager.network("→ POST /\(endpoint) (raw data)")

        do {
            let (data, response) = try await performRequest(urlRequest)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                LogManager.error("HTTP \(http.statusCode) /\(endpoint) (\(data.count) bytes)")
            }
            try validateResponse(response)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            LogManager.network("← POST /\(endpoint) [\(statusCode)] \(data.count) bytes")
            return data
        } catch let error as APIError {
            LogManager.error("Raw request failed /\(endpoint): \(error.localizedDescription)")
            throw error
        }
    }

    func downloadData(from url: URL) async throws -> (data: Data, mimeType: String) {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        guard data.count <= 25 * 1_024 * 1_024 else { throw APIError.invalidResponse }
        return (data, response.mimeType ?? "application/octet-stream")
    }
}

// MARK: - Private

private extension APIClient {
    func buildRequest(
        endpoint: String,
        method: HTTPMethod,
        body: (any Encodable & Sendable)?,
        queryItems: [URLQueryItem]? = nil,
        timeoutInterval: TimeInterval = 60
    ) throws -> URLRequest {
        let baseURL = serverBaseURLProvider()

        let url: URL
        if let queryItems, !queryItems.isEmpty {
            guard let endpointURL = URL(string: baseURL)?.appendingPathComponent(endpoint),
                  var components = URLComponents(
                      url: endpointURL,
                      resolvingAgainstBaseURL: false
                  ) else {
                throw APIError.invalidURL
            }
            components.queryItems = queryItems
            guard let builtURL = components.url else {
                throw APIError.invalidURL
            }
            url = builtURL
        } else {
            guard let builtURL = URL(string: baseURL)?.appendingPathComponent(endpoint) else {
                throw APIError.invalidURL
            }
            url = builtURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = timeoutInterval

        let apiKey = apiKeyProvider()
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        return request
    }

    func request<T: Decodable & Sendable>(
        endpoint: String,
        method: HTTPMethod,
        body: (any Encodable & Sendable)?,
        queryItems: [URLQueryItem]?
    ) async throws -> T {
        let urlRequest = try buildRequest(endpoint: endpoint, method: method, body: body, queryItems: queryItems)
        LogManager.network("→ \(method.rawValue) /\(endpoint)")

        do {
            let (data, response) = try await performRequest(urlRequest)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                LogManager.error("HTTP \(http.statusCode) /\(endpoint) (\(data.count) bytes)")
            }
            try validateResponse(response)

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            LogManager.network("← \(method.rawValue) /\(endpoint) [\(statusCode)] \(data.count) bytes")

            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                return try decoder.decode(T.self, from: data)
            } catch {
                LogManager.error("Decoding failed for /\(endpoint): \(error)")
                throw APIError.decodingError
            }
        } catch let error as APIError {
            LogManager.error("Request failed /\(endpoint): \(error.localizedDescription)")
            throw error
        }
    }

    func parseArgumentsJSON(_ arguments: String) throws -> [String: MCPCallValue] {
        guard let data = arguments.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: MCPCallValue].self, from: data) else {
            throw APIError.invalidRequest(String(localized: "The MCP tool arguments are not valid JSON."))
        }
        return dict
    }

    func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            throw mapURLError(error)
        }
    }

    func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            LogManager.error("Invalid response — not an HTTPURLResponse")
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            LogManager.warning("HTTP 401 Unauthorized")
            throw APIError.unauthorized
        case 429:
            LogManager.warning("HTTP 429 Rate Limited")
            throw APIError.rateLimited
        default:
            LogManager.error("HTTP \(httpResponse.statusCode) error")
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    func mapError(_ error: Error) -> Error {
        if error is APIError {
            return error
        }
        if let urlError = error as? URLError {
            return mapURLError(urlError)
        }
        return error
    }

    func mapURLError(_ error: URLError) -> APIError {
        LogManager.error("URLError \(error.code.rawValue): \(error.localizedDescription)")
        switch error.code {
        case .cannotFindHost, .dnsLookupFailed:
            return .networkError(String(localized: "Could not find the server. Please check the URL."))
        case .cannotConnectToHost:
            return .networkError(String(localized: "Could not connect to the server."))
        case .notConnectedToInternet:
            return .networkError(String(localized: "No internet connection. Please check your network."))
        case .timedOut:
            return .networkError(String(localized: "The request timed out. The server may be slow or unreachable."))
        case .networkConnectionLost:
            return .networkError(String(localized: "The network connection was lost."))
        case .secureConnectionFailed:
            return .networkError(String(localized: "Could not establish a secure connection to the server."))
        case .serverCertificateUntrusted, .serverCertificateHasBadDate,
            .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
            return .networkError(String(localized: "The server certificate is not trusted."))
        case .cancelled:
            return .networkError(String(localized: "The request was cancelled."))
        default:
            return .networkError(String(localized: "A network error occurred. Please try again."))
        }
    }
}
