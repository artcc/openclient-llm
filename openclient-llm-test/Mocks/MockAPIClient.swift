//
//  MockAPIClient.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation
@testable import openclient_llm

// Safety: Only used within serialized @MainActor test methods.
final class MockAPIClient: APIClientProtocol, @unchecked Sendable {
    // MARK: - Properties

    var requestResult: Any?
    var requestError: Error?
    var lastRequestEndpoint: String?
    var lastRequestTimeoutInterval: TimeInterval?
    var lastRequestBody: (any Encodable & Sendable)?
    var lastMCPServerId: String?
    var lastMCPToolName: String?
    var lastMCPArguments: String?
    var streamChunks: [Data] = []
    var streamError: Error?
    var lastStreamEndpoint: String?
    var lastStreamBody: (any Encodable & Sendable)?
    var multipartResult: Any?
    var multipartError: Error?
    var lastMultipartEndpoint: String?
    var lastMultipartFields: [String: String]?
    var lastMultipartFiles: [MultipartFileData]?
    var lastMultipartTimeoutInterval: TimeInterval?
    var rawDataResult: Data?
    var rawDataError: Error?
    var downloadResult: (data: Data, mimeType: String)?
    var downloadError: Error?

    // MARK: - Public

    func request<T: Decodable & Sendable>(
        endpoint: String,
        method: HTTPMethod,
        body: (any Encodable & Sendable)?,
        timeoutInterval: TimeInterval
    ) async throws -> T {
        lastRequestEndpoint = endpoint
        lastRequestTimeoutInterval = timeoutInterval
        lastRequestBody = body
        if let error = requestError {
            throw error
        }
        guard let result = requestResult as? T else {
            throw APIError.decodingError
        }
        return result
    }

    func streamRequest(
        endpoint: String,
        body: any Encodable & Sendable
    ) -> AsyncThrowingStream<Data, Error> {
        lastStreamEndpoint = endpoint
        lastStreamBody = body
        let chunks = streamChunks
        let error = streamError
        return AsyncThrowingStream { continuation in
            Task {
                for chunk in chunks {
                    continuation.yield(chunk)
                }
                if let error {
                    continuation.finish(throwing: error)
                } else {
                    continuation.finish()
                }
            }
        }
    }

    func multipartRequest<T: Decodable & Sendable>(
        endpoint: String,
        fields: [String: String],
        files: [MultipartFileData],
        timeoutInterval: TimeInterval
    ) async throws -> T {
        lastMultipartEndpoint = endpoint
        lastMultipartFields = fields
        lastMultipartFiles = files
        lastMultipartTimeoutInterval = timeoutInterval
        if let error = multipartError {
            throw error
        }
        guard let result = multipartResult as? T else {
            throw APIError.decodingError
        }
        return result
    }

    func rawDataRequest(
        endpoint: String,
        body: any Encodable & Sendable
    ) async throws -> Data {
        if let error = rawDataError {
            throw error
        }
        return rawDataResult ?? Data()
    }

    func downloadData(from url: URL) async throws -> (data: Data, mimeType: String) {
        if let downloadError { throw downloadError }
        guard let downloadResult else { throw APIError.invalidResponse }
        return downloadResult
    }

    func searchRequest(
        toolName: String,
        body: LiteLLMSearchRequest
    ) async throws -> LiteLLMSearchResponse {
        if let error = requestError {
            throw error
        }
        guard let result = requestResult as? LiteLLMSearchResponse else {
            throw APIError.decodingError
        }
        return result
    }

    func fetchSearchTools() async throws -> SearchToolsResponse {
        if let error = requestError {
            throw error
        }
        guard let result = requestResult as? SearchToolsResponse else {
            throw APIError.decodingError
        }
        return result
    }

    func listMCPServers() async throws -> [MCPServerInfo] {
        if let error = requestError {
            throw error
        }
        guard let result = requestResult as? [MCPServerInfo] else {
            throw APIError.decodingError
        }
        return result
    }

    func listMCPTools(serverId: String) async throws -> [MCPToolInfo] {
        lastMCPServerId = serverId
        if let error = requestError {
            throw error
        }
        guard let result = requestResult as? [MCPToolInfo] else {
            throw APIError.decodingError
        }
        return result
    }

    func callMCPTool(serverId: String, toolName: String, arguments: String) async throws -> String {
        lastMCPServerId = serverId
        lastMCPToolName = toolName
        lastMCPArguments = arguments
        if let error = requestError {
            throw error
        }
        guard let result = requestResult as? String else {
            throw APIError.decodingError
        }
        return result
    }
}
