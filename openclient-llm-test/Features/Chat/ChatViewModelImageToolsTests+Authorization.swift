//
//  ChatViewModelImageToolsTests+Authorization.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

extension ChatViewModelImageToolsTests {
    func test_analyzeImages_revokedAfterAuthorization_removesDefinitionAndRejectsExecution() async throws {
        // Given
        let image = imageAttachment()
        let sut = makeViewModel(pending: [image])
        try await sendMessage(sut)
        let registry = try capturedRegistry()
        let invocation = try await authorizedInvocation(
            registry, name: "analyze_images", arguments: analysisArguments(ids: [image.id])
        )
        XCTAssertTrue(registry.definitions.contains { $0.function.name == "analyze_images" })

        // When
        settings.setSelectedVisionModelId(nil)

        // Then
        XCTAssertEqual(try visualToolNames(sut), ["generate_image"])
        XCTAssertFalse(registry.definitions.contains { $0.function.name == "analyze_images" })
        do {
            _ = try await registry.execute(invocation)
            XCTFail("Expected revoked analysis to be rejected")
        } catch {
            XCTAssertEqual(error as? AnalyzeImagesTool.ExecutionError, .unavailable)
        }
        XCTAssertNil(apiClient.lastRequestBody)
        XCTAssertEqual(specialistGeneration.executeCallCount, 0)
    }

    func test_generateImage_revokedAfterAuthorization_removesDefinitionAndRejectsExecution() async throws {
        // Given
        let sut = makeViewModel(pending: [imageAttachment()])
        try await sendMessage(sut)
        let registry = try capturedRegistry()
        let invocation = try await authorizedInvocation(
            registry, name: "generate_image", arguments: #"{"prompt":"A cat"}"#
        )
        XCTAssertTrue(registry.definitions.contains { $0.function.name == "generate_image" })

        // When
        settings.setSelectedImageGenerationModelId(nil)

        // Then
        XCTAssertEqual(try visualToolNames(sut), ["analyze_images", "list_image_attachments"])
        XCTAssertFalse(registry.definitions.contains { $0.function.name == "generate_image" })
        do {
            _ = try await registry.execute(invocation)
            XCTFail("Expected revoked generation to be rejected")
        } catch {
            XCTAssertEqual(error as? GenerateImageTool.ExecutionError, .unavailable)
        }
        XCTAssertEqual(specialistGeneration.executeCallCount, 0)
        XCTAssertEqual(nativeGeneration.executeCallCount, 0)
    }

    func test_imageTools_endpointChanged_invalidatesCapturedRegistryAndAgentConfiguration() async throws {
        // Given
        let image = imageAttachment()
        let sut = makeViewModel(pending: [image])
        try await sendMessage(sut)
        let context = try XCTUnwrap(agent.receivedToolContext)
        XCTAssertTrue(context.isConfigurationCurrent())
        let analyze = try await authorizedInvocation(
            context.toolRegistry, name: "analyze_images", arguments: analysisArguments(ids: [image.id])
        )
        let generate = try await authorizedInvocation(
            context.toolRegistry, name: "generate_image", arguments: #"{"prompt":"A cat"}"#
        )

        // When
        settings.setServerBaseURL("https://other.example.com")

        // Then
        XCTAssertFalse(context.isConfigurationCurrent())
        XCTAssertTrue(try visualToolNames(sut).isEmpty)
        XCTAssertFalse(context.toolRegistry.definitions.contains {
            ["analyze_images", "generate_image", "list_image_attachments"].contains($0.function.name)
        })
        await assertUnavailable(context.toolRegistry, analyze: analyze, generate: generate)
    }

    func test_agentToolDefinitions_missingOrStaleCatalogScope_doesNotAdvertiseSpecialists() throws {
        // Given
        let sut = makeViewModel(pending: [imageAttachment()])
        XCTAssertEqual(try visualToolNames(sut), ["analyze_images", "generate_image", "list_image_attachments"])

        // When / Then
        for scope in [nil, "stale-scope"] as [String?] {
            var state = try loadedState(sut)
            state.modelCatalogScope = scope
            sut.state = .loaded(state)
            XCTAssertTrue(try visualToolNames(sut).isEmpty)
        }
        XCTAssertNil(apiClient.lastRequestBody)
        XCTAssertEqual(specialistGeneration.executeCallCount, 0)
    }

    func test_imageTools_catalogScopeChanged_rejectsPreviouslyAuthorizedInvocations() async throws {
        // Given
        let image = imageAttachment()
        let sut = makeViewModel(pending: [image])
        try await sendMessage(sut)
        let registry = try capturedRegistry()
        let analyze = try await authorizedInvocation(
            registry, name: "analyze_images", arguments: analysisArguments(ids: [image.id])
        )
        let generate = try await authorizedInvocation(
            registry, name: "generate_image", arguments: #"{"prompt":"A cat"}"#
        )

        // When
        var state = try loadedState(sut)
        state.modelCatalogScope = "different-catalog"
        sut.state = .loaded(state)

        // Then
        XCTAssertTrue(try visualToolNames(sut).isEmpty)
        await assertUnavailable(registry, analyze: analyze, generate: generate)
    }

    func test_analyzeImages_settingsRevokedWhileLoadingHistory_stopsBeforeSpecialistRequest() async throws {
        // Given
        let conversationId = UUID()
        let image = imageAttachment(conversationId: conversationId, data: nil)
        let conversation = Conversation(id: conversationId, modelId: principal.id, messages: [
            ChatMessage(role: .user, content: "Historical image", attachments: [image])
        ])
        let sut = makeViewModel(conversation: conversation)
        try await sendMessage(sut)
        let registry = try capturedRegistry()
        let invocation = try await authorizedInvocation(
            registry, name: "analyze_images", arguments: analysisArguments(ids: [image.id])
        )
        var didLoad = false
        attachments.loadHandler = { [settings] _ in
            didLoad = true
            settings.setSelectedVisionModelId(nil)
            return Data([1, 2, 3])
        }

        // When / Then
        do {
            _ = try await registry.execute(invocation)
            XCTFail("Expected analysis to stop after settings changed")
        } catch {
            XCTAssertEqual(error as? AnalyzeImagesTool.ExecutionError, .unavailable)
        }
        XCTAssertTrue(didLoad)
        XCTAssertNil(apiClient.lastRequestBody)
        XCTAssertEqual(try visualToolNames(sut), ["generate_image"])
    }

    func test_imageTools_conversationChanged_rejectsCapturedAttachments() async throws {
        // Given
        let image = imageAttachment()
        let sut = makeViewModel(pending: [image])
        try await sendMessage(sut)
        let registry = try capturedRegistry()
        let analyze = try await authorizedInvocation(
            registry, name: "analyze_images", arguments: analysisArguments(ids: [image.id])
        )
        let generate = try await authorizedInvocation(
            registry, name: "generate_image", arguments: #"{"prompt":"A cat"}"#
        )

        // When
        sut.send(.conversationLoaded(Conversation(modelId: principal.id)))

        // Then
        await assertUnavailable(registry, analyze: analyze, generate: generate)
    }

    // MARK: - Private

    private func assertUnavailable(
        _ registry: ToolRegistry,
        analyze: ToolRegistry.AuthorizedInvocation,
        generate: ToolRegistry.AuthorizedInvocation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await registry.execute(analyze)
            XCTFail("Expected unavailable analysis", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? AnalyzeImagesTool.ExecutionError, .unavailable, file: file, line: line)
        }
        do {
            _ = try await registry.execute(generate)
            XCTFail("Expected unavailable generation", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? GenerateImageTool.ExecutionError, .unavailable, file: file, line: line)
        }
        XCTAssertNil(apiClient.lastRequestBody, file: file, line: line)
        XCTAssertEqual(specialistGeneration.executeCallCount, 0, file: file, line: line)
        XCTAssertEqual(nativeGeneration.executeCallCount, 0, file: file, line: line)
    }
}
