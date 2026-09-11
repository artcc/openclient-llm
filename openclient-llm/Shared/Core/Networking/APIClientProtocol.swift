//
//  APIClientProtocol.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 14/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

struct MultipartFileData: Sendable {
    let field: String
    let data: Data
    let fileName: String
    let mimeType: String
}

protocol APIClientProtocol: Sendable {
    func request<T: Decodable & Sendable>(
        endpoint: String,
        method: HTTPMethod,
        body: (any Encodable & Sendable)?,
        timeoutInterval: TimeInterval
    ) async throws -> T
    func streamRequest(
        endpoint: String,
        body: any Encodable & Sendable
    ) -> AsyncThrowingStream<Data, Error>
    func multipartRequest<T: Decodable & Sendable>(
        endpoint: String,
        fields: [String: String],
        files: [MultipartFileData],
        timeoutInterval: TimeInterval
    ) async throws -> T
    func rawDataRequest(
        endpoint: String,
        body: any Encodable & Sendable
    ) async throws -> Data
    func downloadData(from url: URL) async throws -> (data: Data, mimeType: String)
    func searchRequest(
        toolName: String,
        body: LiteLLMSearchRequest
    ) async throws -> LiteLLMSearchResponse
    func fetchSearchTools() async throws -> SearchToolsResponse
    func listMCPServers() async throws -> [MCPServerInfo]
    func listMCPTools(serverId: String) async throws -> [MCPToolInfo]
    func callMCPTool(serverId: String, toolName: String, arguments: String) async throws -> String
}

extension APIClientProtocol {
    func request<T: Decodable & Sendable>(
        endpoint: String,
        method: HTTPMethod,
        body: (any Encodable & Sendable)?
    ) async throws -> T {
        try await request(endpoint: endpoint, method: method, body: body, timeoutInterval: 60)
    }

    func multipartRequest<T: Decodable & Sendable>(
        endpoint: String,
        fields: [String: String],
        file: MultipartFileData
    ) async throws -> T {
        try await multipartRequest(endpoint: endpoint, fields: fields, files: [file], timeoutInterval: 125)
    }
}

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
}
