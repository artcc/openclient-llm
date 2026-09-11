//
//  ChatViewModelImageToolsTests+BuiltInSettings.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 11/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
extension ChatViewModelImageToolsTests {
    func test_agentToolDefinitions_individualBuiltInDisabled_omitsOnlyThatTool() throws {
        // Given
        let sut = makeViewModel(pending: [imageAttachment()])
        var state = try loadedState(sut)
        state.isWebSearchEnabled = true
        sut.state = .loaded(state)
        let allNames = Set(BuiltInTool.allCases.map(\.rawValue))
        XCTAssertEqual(Set(sut.agentToolDefinitions(for: state).map(\.function.name)), allNames)

        for tool in BuiltInTool.allCases {
            // When
            settings.disabledBuiltInTools = [tool]
            let names = Set(sut.agentToolDefinitions(for: state).map(\.function.name))

            // Then
            XCTAssertEqual(names, allNames.subtracting([tool.rawValue]))
        }
    }

    func test_requestSystemPrompt_allBuiltInsDisabled_omitsTheirInstructions() {
        // Given
        settings.disabledBuiltInTools = Set(BuiltInTool.allCases)
        let sut = makeViewModel()

        // When
        let prompt = sut.requestSystemPrompt("", modelCapabilities: [.functionCalling], webSearchEnabled: true)

        // Then
        for tool in BuiltInTool.allCases {
            XCTAssertFalse(prompt.contains(tool.rawValue))
        }
    }

    func test_agentToolDefinitions_privateChatWithAllToolsEnabled_keepsMemoryUnavailable() throws {
        // Given
        let sut = makeViewModel(isPrivate: true)

        // When
        let names = Set(sut.agentToolDefinitions(for: try loadedState(sut)).map(\.function.name))

        // Then
        XCTAssertFalse(names.contains("save_memory"))
        XCTAssertFalse(names.contains("delete_memory"))
        XCTAssertTrue(names.contains("get_current_datetime"))
    }

    func test_send_webSearchToggledWithBuiltInDisabled_doesNotEnableSearch() throws {
        // Given
        settings.disabledBuiltInTools = [.webSearch]
        let sut = makeViewModel()
        var state = try loadedState(sut)
        state.isWebSearchToolConfigured = true
        sut.state = .loaded(state)

        // When
        sut.send(.webSearchToggled)

        // Then
        XCTAssertFalse(try loadedState(sut).isWebSearchEnabled)
    }

    func test_agentToolDefinitions_allBuiltInsDisabled_keepsEnabledMCPTool() throws {
        // Given
        settings.disabledBuiltInTools = Set(BuiltInTool.allCases)
        let tool = MCPToolInfo(
            name: "current", description: nil, serverId: "server", serverName: "Server", inputSchema: nil
        )
        settings.enabledMCPToolIds = [tool.id]
        settings.mcpToolConfigurationKeys[tool.id] = tool.permissionKey(
            serverBaseURL: settings.serverBaseURL,
            authorizationScope: settings.mcpAuthorizationScope
        )
        let sut = makeViewModel()
        var state = try loadedState(sut)
        state.availableMCPTools = [tool]
        state.enabledMCPToolIds = [tool.id]
        state.mcpDiscoveryScope = settings.mcpAuthorizationScope
        sut.state = .loaded(state)

        // When
        let definitions = sut.agentToolDefinitions(for: state)

        // Then
        XCTAssertEqual(definitions.map(\.function.name), [tool.prefixedName])
    }
}
