//
//  ToolRegistryTests.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 31/07/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class ToolRegistryTests: XCTestCase {
    // MARK: - Tests — init / definitions

    func test_init_withEmptyTools_producesEmptyDefinitions() {
        let sut = ToolRegistry(tools: [])
        XCTAssertTrue(sut.definitions.isEmpty)
    }

    func test_init_withTools_producesCorrectDefinitions() {
        let tool = MockChatTool(name: "test_tool")
        let sut = ToolRegistry(tools: [tool])
        XCTAssertEqual(sut.definitions.count, 1)
        XCTAssertEqual(sut.definitions.first?.function.name, "test_tool")
    }

    // MARK: - Tests — execute

    func test_execute_knownTool_delegatesToTool() async throws {
        // Given
        let tool = MockChatTool(name: "greet", executionResult: ToolExecutionResult(text: "hello"))
        let sut = ToolRegistry(tools: [tool])

        // When
        let invocation = try await authorizedInvocation(
            in: sut,
            toolName: "greet",
            arguments: "{}"
        )
        let result = try await sut.execute(invocation)

        // Then
        XCTAssertEqual(result.text, "hello")
        XCTAssertEqual(tool.lastArguments, "{}")
    }

    func test_execute_unknownTool_returnsErrorText() async throws {
        // Given
        let sut = ToolRegistry(tools: [])

        // When
        let invocation = try await authorizedInvocation(
            in: sut,
            toolName: "nonexistent",
            arguments: "{}"
        )
        let result = try await sut.execute(invocation)

        // Then
        XCTAssertTrue(result.text.contains("Unknown tool"))
    }

    func test_makeAuthorizationPlan_internalAndWebTools_areAlwaysAutomatic() async throws {
        // Given
        let names = ["get_current_datetime", "save_memory", "delete_memory", "web_search"]
        let sut = ToolRegistry(tools: names.map { MockChatTool(name: $0) })
        let calls = names.enumerated().map { index, name in
            ToolCall(
                id: "call-\(index)",
                type: "function",
                function: ToolCallFunction(name: name, arguments: "{}")
            )
        }

        // When
        let plan = sut.makeAuthorizationPlan(for: calls)
        let outcomes = try await sut.resolveAuthorization(plan)

        // Then
        XCTAssertFalse(plan.requiresUserDecision)
        XCTAssertEqual(outcomes.count, calls.count)
        for outcome in outcomes {
            guard case .authorized = outcome else {
                XCTFail("Internal and web tools must remain automatic")
                return
            }
        }
    }

    func test_execute_sameAuthorizedInvocationTwice_rejectsSecondExecution() async throws {
        // Given
        let tool = MockChatTool(name: "single_use")
        let sut = ToolRegistry(tools: [tool])
        let invocation = try await authorizedInvocation(
            in: sut,
            toolName: "single_use",
            arguments: "{}"
        )

        // When
        _ = try await sut.execute(invocation)
        do {
            _ = try await sut.execute(invocation)
            XCTFail("Expected the permit to be single-use")
        } catch {
            // Expected
        }

        // Then
        XCTAssertEqual(tool.executionCount, 1)
    }

    func test_execute_mcpPermissionChangesAfterPlanning_blocksExecution() async throws {
        // Given
        let state = RegistryMCPState()
        let repository = MockRegistryMCPRepository()
        let tool = MCPTool(
            serverId: "github",
            toolName: "GitHub-create_issue",
            rawName: "create_issue",
            description: "Create an issue",
            parameters: ToolParameters(type: "object", properties: [:], required: []),
            repository: repository,
            permissionProvider: { state.permission },
            isEnabled: { state.isEnabled }
        )
        let sut = ToolRegistry(tools: [tool])
        let invocation = try await authorizedInvocation(
            in: sut,
            toolName: "GitHub-create_issue",
            arguments: "{}"
        )

        // When
        state.permission = .deny
        do {
            _ = try await sut.execute(invocation)
            XCTFail("Expected changed permission to block execution")
        } catch {
            // Expected
        }

        // Then
        XCTAssertFalse(repository.didExecute)
    }

    func test_execute_mcpDisabledAfterPlanning_blocksExecution() async throws {
        // Given
        let state = RegistryMCPState()
        let repository = MockRegistryMCPRepository()
        let tool = MCPTool(
            serverId: "github",
            toolName: "GitHub-create_issue",
            rawName: "create_issue",
            description: "Create an issue",
            parameters: ToolParameters(type: "object", properties: [:], required: []),
            repository: repository,
            permissionProvider: { state.permission },
            isEnabled: { state.isEnabled }
        )
        let sut = ToolRegistry(tools: [tool])
        let invocation = try await authorizedInvocation(
            in: sut,
            toolName: "GitHub-create_issue",
            arguments: "{}"
        )

        // When
        state.isEnabled = false
        do {
            _ = try await sut.execute(invocation)
            XCTFail("Expected disabled tool to block execution")
        } catch {
            // Expected
        }

        // Then
        XCTAssertFalse(repository.didExecute)
    }

    func test_definitions_mcpDisabledAfterRegistryCreation_excludesTool() {
        // Given
        let state = RegistryMCPState()
        let tool = MCPTool(
            serverId: "github",
            toolName: "GitHub-create_issue",
            rawName: "create_issue",
            description: "Create an issue",
            parameters: ToolParameters(type: "object", properties: [:], required: []),
            permissionProvider: { state.permission },
            isEnabled: { state.isEnabled }
        )
        let sut = ToolRegistry(tools: [tool])
        let initialDefinitions = sut.definitions

        // When
        state.isEnabled = false
        let updatedDefinitions = sut.definitions

        // Then
        XCTAssertEqual(initialDefinitions.count, 1)
        XCTAssertTrue(updatedDefinitions.isEmpty)
    }

    func test_definitions_mcpConfigurationChangesAfterRegistryCreation_excludesTool() {
        // Given
        let state = RegistryMCPState()
        let tool = MCPTool(
            serverId: "github",
            toolName: "GitHub-create_issue",
            rawName: "create_issue",
            description: "Create an issue",
            parameters: ToolParameters(type: "object", properties: [:], required: []),
            permissionProvider: { state.permission },
            isConfigurationCurrent: { state.isConfigurationCurrent }
        )
        let sut = ToolRegistry(tools: [tool])
        let initialDefinitions = sut.definitions

        // When
        state.isConfigurationCurrent = false
        let updatedDefinitions = sut.definitions

        // Then
        XCTAssertEqual(initialDefinitions.count, 1)
        XCTAssertTrue(updatedDefinitions.isEmpty)
    }

    func test_definitions_mcpDeniedByPolicy_keepsToolAdvertised() {
        // Given
        let tool = MCPTool(
            serverId: "github",
            toolName: "GitHub-create_issue",
            rawName: "create_issue",
            description: "Create an issue",
            parameters: ToolParameters(type: "object", properties: [:], required: []),
            permission: .deny
        )
        let sut = ToolRegistry(tools: [tool])

        // When
        let definitions = sut.definitions

        // Then
        XCTAssertEqual(definitions.map(\.function.name), ["GitHub-create_issue"])
    }

    func test_execute_cancelledAfterAuthorization_doesNotExecuteMCPTool() async throws {
        // Given
        let state = RegistryMCPState()
        let repository = MockRegistryMCPRepository()
        let tool = MCPTool(
            serverId: "github",
            toolName: "GitHub-create_issue",
            rawName: "create_issue",
            description: "Create an issue",
            parameters: ToolParameters(type: "object", properties: [:], required: []),
            repository: repository,
            permissionProvider: { state.permission }
        )
        let sut = ToolRegistry(tools: [tool])
        let invocation = try await authorizedInvocation(
            in: sut,
            toolName: "GitHub-create_issue",
            arguments: "{}"
        )

        // When
        let execution = Task { try await sut.execute(invocation) }
        execution.cancel()
        _ = try? await execution.value

        // Then
        XCTAssertFalse(repository.didExecute)
    }

    // MARK: - Tests — built-in settings

    func test_execute_builtInDisabledAfterAuthorization_doesNotExecute() async throws {
        // Given
        let settings = MockSettingsManager()
        let tool = MockChatTool(name: "save_memory")
        let sut = ToolRegistry(tools: [ConfiguredBuiltInTool(tool: tool, settingsManager: settings)])
        let invocation = try await authorizedInvocation(in: sut, toolName: "save_memory", arguments: "{}")

        // When
        settings.setIsBuiltInToolEnabled(false, for: .saveMemory)
        let result = try await sut.execute(invocation)

        // Then
        XCTAssertEqual(tool.executionCount, 0)
        XCTAssertTrue(sut.definitions.isEmpty)
        XCTAssertTrue(result.text.contains("disabled"))
    }

    func test_definitions_builtInReenabled_restoresAdvertisementAndExecution() async throws {
        // Given
        let settings = MockSettingsManager()
        settings.setIsBuiltInToolEnabled(false, for: .saveMemory)
        let tool = MockChatTool(name: "save_memory")
        let sut = ToolRegistry(tools: [ConfiguredBuiltInTool(tool: tool, settingsManager: settings)])
        XCTAssertTrue(sut.definitions.isEmpty)

        // When
        settings.setIsBuiltInToolEnabled(true, for: .saveMemory)
        let invocation = try await authorizedInvocation(in: sut, toolName: "save_memory", arguments: "{}")
        _ = try await sut.execute(invocation)

        // Then
        XCTAssertEqual(sut.definitions.map(\.function.name), ["save_memory"])
        XCTAssertEqual(tool.executionCount, 1)
    }

    func test_definitions_enabledBuiltInWithUnavailableImplementation_remainsUnavailable() {
        // Given
        let settings = MockSettingsManager()
        let tool = ListImageAttachmentsTool(attachments: [], isAvailable: { false })
        let sut = ToolRegistry(tools: [ConfiguredBuiltInTool(tool: tool, settingsManager: settings)])

        // When
        let definitions = sut.definitions

        // Then
        XCTAssertTrue(definitions.isEmpty)
    }

    // MARK: - Tests — default factory

    func test_default_withWebSearchEnabled_includesWebSearchTool() {
        let sut = ToolRegistry.default(webSearchEnabled: true)
        let names = sut.definitions.map(\.function.name)
        XCTAssertTrue(names.contains("web_search"))
    }

    func test_default_withWebSearchDisabled_excludesWebSearchTool() {
        let sut = ToolRegistry.default(webSearchEnabled: false)
        let names = sut.definitions.map(\.function.name)
        XCTAssertFalse(names.contains("web_search"))
    }

    func test_default_alwaysIncludesGetCurrentDatetimeTool() {
        let sut = ToolRegistry.default()
        let names = sut.definitions.map(\.function.name)
        XCTAssertTrue(names.contains("get_current_datetime"))
    }

    func test_default_withMemoryToolsEnabled_includesMemoryTools() {
        let sut = ToolRegistry.default(includesMemoryTools: true)
        let names = sut.definitions.map(\.function.name)
        XCTAssertTrue(names.contains("save_memory"))
        XCTAssertTrue(names.contains("delete_memory"))
    }

    func test_default_withMemoryToolsDisabled_excludesMemoryTools() {
        let sut = ToolRegistry.default(includesMemoryTools: false)
        let names = sut.definitions.map(\.function.name)
        XCTAssertFalse(names.contains("save_memory"))
        XCTAssertFalse(names.contains("delete_memory"))
    }
}

private extension ToolRegistryTests {
    func authorizedInvocation(
        in registry: ToolRegistry,
        toolName: String,
        arguments: String
    ) async throws -> ToolRegistry.AuthorizedInvocation {
        let toolCall = ToolCall(
            id: "test-call",
            type: "function",
            function: ToolCallFunction(name: toolName, arguments: arguments)
        )
        let outcomes = try await registry.resolveAuthorization(
            registry.makeAuthorizationPlan(for: [toolCall])
        )
        guard let outcome = outcomes.first,
              case .authorized(let invocation) = outcome else {
            throw TestError.notAuthorized
        }
        return invocation
    }

    enum TestError: Error {
        case notAuthorized
    }
}

// MARK: - MockChatTool

// Safety: Only used within serialized @MainActor test methods.
private final class MockChatTool: ChatToolProtocol, @unchecked Sendable {
    let toolName: String
    var executionResult: ToolExecutionResult = ToolExecutionResult(text: "mock")
    var lastArguments: String?
    var executionCount = 0

    var definition: ToolDefinition {
        ToolDefinition(
            type: "function",
            function: ToolFunctionDefinition(
                name: toolName,
                description: "Mock tool",
                parameters: ToolParameters(type: "object", properties: [:], required: [])
            )
        )
    }

    init(name: String, executionResult: ToolExecutionResult = ToolExecutionResult(text: "mock")) {
        self.toolName = name
        self.executionResult = executionResult
    }

    func execute(arguments: String) async throws -> ToolExecutionResult {
        executionCount += 1
        lastArguments = arguments
        return executionResult
    }
}

@MainActor
private final class RegistryMCPState {
    var permission: MCPToolPermission = .alwaysAllow
    var isEnabled = true
    var isConfigurationCurrent = true
}

// Safety: Only used within serialized @MainActor test methods.
private final class MockRegistryMCPRepository: MCPRepositoryProtocol, @unchecked Sendable {
    var didExecute = false

    func fetchServers() async throws -> [MCPServerInfo] { [] }
    func fetchTools(serverId: String) async throws -> [MCPToolInfo] { [] }

    func executeTool(serverId: String, toolName: String, arguments: String) async throws -> String {
        didExecute = true
        return "ok"
    }
}
