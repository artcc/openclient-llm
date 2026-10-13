//
//  FetchMCPToolsUseCaseTests.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 31/07/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class FetchMCPToolsUseCaseTests: XCTestCase {
    func test_execute_fetchesToolsByServerId_andAssociatesServerMetadata() async {
        // Given
        let server = MCPServerInfo(
            serverId: "srv-1",
            serverName: "GitHub",
            description: nil,
            allowedTools: nil
        )
        let repository = MockMCPRepository(
            servers: [server],
            toolsByServerId: ["srv-1": [MCPToolInfo(
                name: "search",
                description: "Search",
                serverId: "",
                serverName: "",
                inputSchema: nil
            )]]
        )
        let settings = MockSettingsManager()
        settings.serverBaseURL = "https://example.com"
        let sut = FetchMCPToolsUseCase(repository: repository, settingsManager: settings)

        // When
        let result = await sut.execute()

        // Then
        XCTAssertEqual(repository.requestedServerIds, ["srv-1"])
        XCTAssertEqual(result.tools.first?.serverId, "srv-1")
        XCTAssertEqual(result.tools.first?.serverName, "GitHub")
        XCTAssertNil(result.errorMessage)
    }

    func test_execute_filtersToolsUsingLiteLLMAllowedTools() async {
        // Given
        let server = MCPServerInfo(
            serverId: "srv-1",
            serverName: "GitHub",
            description: nil,
            allowedTools: ["search"]
        )
        let repository = MockMCPRepository(
            servers: [server],
            toolsByServerId: ["srv-1": [
                MCPToolInfo(name: "search", description: nil, serverId: "", serverName: "", inputSchema: nil),
                MCPToolInfo(name: "delete", description: nil, serverId: "", serverName: "", inputSchema: nil)
            ]]
        )
        let settings = MockSettingsManager()
        settings.serverBaseURL = "https://example.com"
        let sut = FetchMCPToolsUseCase(repository: repository, settingsManager: settings)

        // When
        let result = await sut.execute()

        // Then
        XCTAssertEqual(result.tools.map(\.name), ["search"])
    }

    func test_execute_emptyAllowedTools_preservesSuccessfullyDiscoveredTools() async {
        // Given
        let server = MCPServerInfo(
            serverId: "srv-1",
            serverName: "GitHub",
            description: nil,
            allowedTools: []
        )
        let tools = [
            MCPToolInfo(name: "search", description: nil, serverId: "", serverName: "", inputSchema: nil),
            MCPToolInfo(name: "issues", description: nil, serverId: "", serverName: "", inputSchema: nil)
        ]
        let repository = MockMCPRepository(servers: [server], toolsByServerId: [server.serverId: tools])
        let settings = MockSettingsManager()
        settings.serverBaseURL = "https://example.com"
        let sut = FetchMCPToolsUseCase(repository: repository, settingsManager: settings)

        // When
        let result = await sut.execute()

        // Then
        XCTAssertEqual(result.servers, [server])
        XCTAssertEqual(result.tools, tools.map { $0.withServer(server) })
        XCTAssertTrue(result.failedServerIds.isEmpty)
        XCTAssertNil(result.errorMessage)
    }

    func test_execute_emptySuccessfulDiscovery_doesNotRetainPreviousTools() async {
        // Given
        let server = MCPServerInfo(
            serverId: "srv-1",
            serverName: "GitHub",
            description: nil,
            allowedTools: []
        )
        let previousTool = MCPToolInfo(
            name: "search",
            description: nil,
            serverId: server.serverId,
            serverName: server.serverName,
            inputSchema: nil
        )
        let repository = MockMCPRepository(servers: [server], toolsByServerId: [server.serverId: []])
        let settings = MockSettingsManager()
        settings.serverBaseURL = "https://example.com"
        let sut = FetchMCPToolsUseCase(repository: repository, settingsManager: settings)

        // When
        let result = await sut.execute()

        // Then
        XCTAssertEqual(result.servers, [server])
        XCTAssertTrue(result.tools.isEmpty)
        XCTAssertTrue(result.failedServerIds.isEmpty)
        XCTAssertNil(result.errorMessage)
        XCTAssertTrue(result.mergingPreviouslyDiscoveredTools([previousTool]).isEmpty)
    }

    func test_execute_whenOneServerFails_keepsOtherServersAndReportsWarning() async {
        // Given
        let goodServer = MCPServerInfo(serverId: "good", serverName: "Good", description: nil, allowedTools: nil)
        let badServer = MCPServerInfo(serverId: "bad", serverName: "Bad", description: nil, allowedTools: nil)
        let repository = MockMCPRepository(
            servers: [goodServer, badServer],
            toolsByServerId: ["good": [MCPToolInfo(
                name: "search",
                description: nil,
                serverId: "",
                serverName: "",
                inputSchema: nil
            )]],
            failingServerIds: ["bad", "Bad"]
        )
        let settings = MockSettingsManager()
        settings.serverBaseURL = "https://example.com"
        let sut = FetchMCPToolsUseCase(repository: repository, settingsManager: settings)

        // When
        let result = await sut.execute()

        // Then
        XCTAssertEqual(result.servers.count, 2)
        XCTAssertEqual(result.tools.map(\.serverId), ["good"])
        XCTAssertNotNil(result.errorMessage)
    }

    func test_execute_multipleServers_startsConcurrentlyAndPreservesServerOrder() async {
        // Given
        let servers = [
            MCPServerInfo(serverId: "first", serverName: "First", description: nil, allowedTools: nil),
            MCPServerInfo(serverId: "second", serverName: "Second", description: nil, allowedTools: nil)
        ]
        let gate = MCPDiscoveryGate()
        let settings = MockSettingsManager()
        settings.serverBaseURL = "https://example.com"
        let sut = FetchMCPToolsUseCase(
            repository: ControlledMCPRepository(servers: servers, gate: gate),
            settingsManager: settings
        )
        let task = Task { await sut.execute() }

        // When
        for _ in 0..<100 {
            if await gate.startedCount == 2 { break }
            await Task.yield()
        }
        let startedCount = await gate.startedCount
        await gate.resume(serverId: "second", toolName: "second_tool")
        await gate.resume(serverId: "first", toolName: "first_tool")
        let result = await task.value

        // Then
        XCTAssertEqual(startedCount, 2)
        XCTAssertEqual(result.tools.map(\.name), ["first_tool", "second_tool"])
    }

    func test_execute_configurationChangesDuringDiscovery_discardsResult() async {
        // Given
        let server = MCPServerInfo(serverId: "server", serverName: "Server", description: nil, allowedTools: nil)
        let gate = MCPDiscoveryGate()
        let settings = MockSettingsManager()
        settings.serverBaseURL = "https://example.com"
        settings.apiKey = "first-key"
        let sut = FetchMCPToolsUseCase(
            repository: ControlledMCPRepository(servers: [server], gate: gate),
            settingsManager: settings
        )
        let task = Task { await sut.execute() }
        for _ in 0..<100 {
            if await gate.startedCount == 1 { break }
            await Task.yield()
        }

        // When
        settings.apiKey = "second-key"
        await gate.resume(serverId: server.serverId, toolName: "stale_tool")
        let result = await task.value

        // Then
        XCTAssertTrue(result.servers.isEmpty)
        XCTAssertTrue(result.tools.isEmpty)
    }
}

@MainActor
private struct ControlledMCPRepository: MCPRepositoryProtocol {
    let servers: [MCPServerInfo]
    let gate: MCPDiscoveryGate

    func fetchServers() async throws -> [MCPServerInfo] { servers }

    func fetchTools(serverId: String) async throws -> [MCPToolInfo] {
        await gate.wait(serverId: serverId)
    }

    func executeTool(serverId: String, toolName: String, arguments: String) async throws -> String { "" }
}

private actor MCPDiscoveryGate {
    private(set) var startedCount = 0
    private var continuations: [String: CheckedContinuation<[MCPToolInfo], Never>] = [:]
    private var queuedTools: [String: [MCPToolInfo]] = [:]

    func wait(serverId: String) async -> [MCPToolInfo] {
        startedCount += 1
        if let tools = queuedTools.removeValue(forKey: serverId) { return tools }
        return await withCheckedContinuation { continuation in
            continuations[serverId] = continuation
        }
    }

    func resume(serverId: String, toolName: String) {
        let tools = [MCPToolInfo(
            name: toolName,
            description: nil,
            serverId: "",
            serverName: "",
            inputSchema: nil
        )]
        if let continuation = continuations.removeValue(forKey: serverId) {
            continuation.resume(returning: tools)
        } else {
            queuedTools[serverId] = tools
        }
    }
}

@MainActor
private final class MockMCPRepository: MCPRepositoryProtocol {
    let servers: [MCPServerInfo]
    let toolsByServerId: [String: [MCPToolInfo]]
    let failingServerIds: Set<String>
    private(set) var requestedServerIds: [String] = []

    init(
        servers: [MCPServerInfo],
        toolsByServerId: [String: [MCPToolInfo]],
        failingServerIds: Set<String> = []
    ) {
        self.servers = servers
        self.toolsByServerId = toolsByServerId
        self.failingServerIds = failingServerIds
    }

    func fetchServers() async throws -> [MCPServerInfo] {
        servers
    }

    func fetchTools(serverId: String) async throws -> [MCPToolInfo] {
        requestedServerIds.append(serverId)
        if failingServerIds.contains(serverId) {
            throw APIError.serverUnreachable
        }
        return toolsByServerId[serverId] ?? []
    }

    func executeTool(serverId: String, toolName: String, arguments: String) async throws -> String {
        ""
    }
}
