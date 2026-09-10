//
//  ChatViewModelImageToolsTests+Inventory.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

extension ChatViewModelImageToolsTests {
    func test_send_320AlreadyCompactedImagesAndTextOnlyTurn_reachesAgentWithin4096TokenContext() async throws {
        // Given
        let model = LLMModel(id: principal.id, capabilities: [.functionCalling], maxInputTokens: 4_096)
        let conversation = try inventoryConversation(imageCount: 320, compacted: true)
        let sut = makeViewModel(model: model, conversation: conversation)
        let oldIDs = conversation.messages.flatMap(\.attachments).map(\.id)
        XCTAssertEqual(oldIDs.count, 320)
        XCTAssertTrue(try loadedState(sut).pendingAttachments.isEmpty)

        // When
        try await sendMessage(sut, prompt: "Describe an earlier image")

        // Then
        XCTAssertEqual(agent.executeCallCount, 1, "Historical UUIDs must not exhaust the preflight tool budget")
        XCTAssertTrue(stream.receivedMessages.isEmpty)
        let request = try XCTUnwrap(agent.receivedMessages.first)
        XCTAssertEqual(request.map(\.role), [.system, .user])
        XCTAssertEqual(request.last?.content, "Describe an earlier image")
        XCTAssertTrue(request.allSatisfy { $0.attachments.isEmpty })
        let requestText = request.map(\.content).joined(separator: "\n")
        XCTAssertTrue(oldIDs.allSatisfy { !requestText.contains($0.uuidString) })
        XCTAssertTrue(requestText.contains(try XCTUnwrap(conversation.contextSummary)))
        let definitions = try capturedRegistry().definitions
        XCTAssertTrue(definitions.contains { $0.function.name == "analyze_images" })
        XCTAssertTrue(definitions.contains { $0.function.name == "list_image_attachments" })
        let state = try loadedState(sut)
        XCTAssertNil(state.errorMessage)
        XCTAssertEqual(state.messages.last?.content, "Response")
        XCTAssertEqual(state.selectedModel, model)
        XCTAssertEqual(Array(state.messages.prefix(conversation.messages.count)), conversation.messages)
        XCTAssertEqual(state.conversation?.contextSummaryCursorMessageId, conversation.messages.last?.id)
    }

    func test_send_oneVersus320CompactedImages_advertisesIdenticalDefinitionsAndConstantTokenCost() async throws {
        // Given
        let model = LLMModel(id: principal.id, capabilities: [.functionCalling], maxInputTokens: 4_096)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var encodedDefinitions: [Data] = []
        var definitionCosts: [Int] = []

        for count in [1, 320] {
            let conversation = try inventoryConversation(imageCount: count, compacted: true)
            let sut = makeViewModel(model: model, conversation: conversation)
            let estimatedDefinitions = sut.agentToolDefinitions(for: try loadedState(sut))

            // When
            try await sendMessage(sut, prompt: "Find an earlier image")

            // Then
            XCTAssertEqual(agent.executeCallCount, encodedDefinitions.count + 1)
            let definitions = try capturedRegistry().definitions
            let analysis = try XCTUnwrap(definitions.first { $0.function.name == "analyze_images" })
            let inventory = try XCTUnwrap(definitions.first { $0.function.name == "list_image_attachments" })
            XCTAssertEqual(analysis.function.parameters.properties["attachment_ids"]?.items?.type, "string")
            XCTAssertNil(analysis.function.parameters.properties["attachment_ids"]?.items?.enum)
            XCTAssertTrue(inventory.function.parameters.required.isEmpty)
            let encoded = try encoder.encode(definitions.sorted { $0.function.name < $1.function.name })
            XCTAssertFalse(try XCTUnwrap(String(data: encoded, encoding: .utf8)).contains("\"enum\""))
            XCTAssertEqual(encoded, try encoder.encode(estimatedDefinitions.sorted {
                $0.function.name < $1.function.name
            }))
            encodedDefinitions.append(encoded)
            definitionCosts.append(ContextWindowBuilder().estimatedInputTokens(
                messages: [], systemPrompt: "", tools: definitions
            ))
            XCTAssertNil(try loadedState(sut).errorMessage)
        }
        XCTAssertEqual(encodedDefinitions.count, 2)
        XCTAssertEqual(encodedDefinitions[0].count, encodedDefinitions[1].count)
        XCTAssertEqual(encodedDefinitions[0], encodedDefinitions[1])
        XCTAssertGreaterThan(definitionCosts[0], 0)
        XCTAssertEqual(definitionCosts[0], definitionCosts[1])
    }

    func test_analyzeImages_page310OfRestoredCompactedHistory_loadsReturnedIDWithSelectedSpecialistLimit()
        async throws {
        // Given
        let model = LLMModel(id: principal.id, capabilities: [.functionCalling], maxInputTokens: 4_096)
        let specialist = LLMModel(id: "limited-vision-specialist", capabilities: [.vision], maxOutputTokens: 1_024)
        settings.setSelectedVisionModelId(specialist.id)
        let restored = try inventoryConversation(imageCount: 320, compacted: true)
        let stored = restored.messages.flatMap(\.attachments)
        let sut = makeViewModel(model: model, conversation: restored, extraModels: [specialist])
        let imageData = Data("restored-image-310".utf8)
        let loads = InventoryLoads()
        attachments.loadHandler = { image in
            loads.ids.append(image.id)
            XCTAssertEqual(image, stored[310])
            return imageData
        }
        try await sendMessage(sut, prompt: "Inspect an image from earlier history")
        XCTAssertEqual(agent.executeCallCount, 1)
        let request = try XCTUnwrap(agent.receivedMessages.first)
        XCTAssertFalse(request.map(\.content).joined().contains(stored[310].id.uuidString))
        let registry = try capturedRegistry()

        // When
        let list = try await authorizedInvocation(
            registry, name: "list_image_attachments", arguments: #"{"offset":310}"#
        )
        let result = try await registry.execute(list)
        let page = try JSONDecoder().decode(InventoryPage.self, from: Data(result.text.utf8))

        // Then
        XCTAssertEqual(page.imageAttachmentIds, Array(stored.suffix(10)).map(\.id))
        XCTAssertEqual(page.offset, 310)
        XCTAssertEqual(page.total, 320)
        XCTAssertNil(page.nextOffset)
        XCTAssertTrue(loads.ids.isEmpty, "Listing must not read image bytes")
        XCTAssertNil(apiClient.lastRequestBody)
        let selectedID = try XCTUnwrap(page.imageAttachmentIds.first)
        let analyze = try await authorizedInvocation(
            registry, name: "analyze_images", arguments: analysisArguments(ids: [selectedID])
        )
        _ = try await registry.execute(analyze)
        XCTAssertEqual(loads.ids, [selectedID])
        let payload = try XCTUnwrap(apiClient.lastRequestBody as? ChatCompletionRequest)
        XCTAssertEqual(payload.model, specialist.id)
        XCTAssertEqual(payload.maxTokens, 1_024)
        XCTAssertEqual(payload.messages.map(\.role), ["system", "user"])
        XCTAssertNil(payload.tools)
        XCTAssertFalse(payload.stream)
        guard case .multimodal(let parts) = try XCTUnwrap(payload.messages.last).content else {
            return XCTFail("Expected the stored image in the specialist payload")
        }
        XCTAssertEqual(parts.compactMap { $0.imageUrl?.url },
            ["data:image/jpeg;base64,\(imageData.base64EncodedString())"]
        )
        XCTAssertTrue(parts.compactMap(\.text).joined().contains(selectedID.uuidString))
        XCTAssertEqual(try loadedState(sut).selectedModel, model)
        XCTAssertEqual(Array(try loadedState(sut).messages.prefix(restored.messages.count)), restored.messages)
    }

    func test_listImageAttachments_visionRevokedAfterAuthorization_rejectsAlongsideAnalysis() async throws {
        // Given
        let conversation = try inventoryConversation(imageCount: 1, compacted: true)
        let sut = makeViewModel(conversation: conversation)
        try await sendMessage(sut)
        let registry = try capturedRegistry()
        let imageID = try XCTUnwrap(conversation.messages.first?.attachments.first?.id)
        let list = try await authorizedInvocation(registry, name: "list_image_attachments", arguments: "{}")
        let analyze = try await authorizedInvocation(
            registry, name: "analyze_images", arguments: analysisArguments(ids: [imageID])
        )
        XCTAssertTrue(registry.definitions.contains { $0.function.name == "list_image_attachments" })

        // When
        settings.setSelectedVisionModelId(nil)

        // Then
        XCTAssertFalse(registry.definitions.contains {
            ["list_image_attachments", "analyze_images"].contains($0.function.name)
        })
        for invocation in [list, analyze] {
            do {
                _ = try await registry.execute(invocation)
                XCTFail("Revoking vision must reject both previously authorized image tools")
            } catch {
                XCTAssertEqual(error as? AnalyzeImagesTool.ExecutionError, .unavailable)
            }
        }
        XCTAssertNil(apiClient.lastRequestBody)
    }

    func test_send_320UncompactedImageTurns_compactsWithToolsAndKeepsHistoricalInventoryReachable() async throws {
        // Given
        let model = LLMModel(id: principal.id, capabilities: [.functionCalling], maxInputTokens: 4_096)
        let conversation = try inventoryConversation(imageCount: 320, compacted: false)
        let compaction = MockCompactConversationUseCase()
        let cursor = try XCTUnwrap(conversation.messages.last?.id)
        compaction.result = CompactedConversation(
            summary: "Earlier images remain uninspected.", cursorMessageId: cursor
        )
        let sut = makeInventoryViewModel(model: model, conversation: conversation, compaction: compaction)
        defer {
            sut.errorDismissTask?.cancel()
            sut.mcpSettingsObservationTask?.cancel()
            sut.mcpDiscoveryTask?.cancel()
            sut.streamTask?.cancel()
        }

        // When
        try await sendMessage(sut, prompt: "Find an earlier image")
        _ = await sut.persistenceTask?.value

        // Then
        XCTAssertEqual(compaction.callCount, 1, "This scenario must exercise actual preflight compaction")
        XCTAssertEqual(agent.executeCallCount, 1, "Compaction must complete before reaching the agent")
        let configuration = try XCTUnwrap(compaction.receivedConfigurations.first)
        XCTAssertNil(configuration.existingSummary)
        XCTAssertNil(configuration.summaryCursorMessageId)
        XCTAssertEqual(configuration.contextWindowTokens, 4_096)
        XCTAssertTrue(configuration.tools.contains { $0.function.name == "analyze_images" })
        XCTAssertTrue(configuration.tools.contains { $0.function.name == "list_image_attachments" })
        let registry = try capturedRegistry()
        let list = try await authorizedInvocation(
            registry, name: "list_image_attachments", arguments: #"{"offset":310}"#
        )
        let result = try await registry.execute(list)
        let page = try JSONDecoder().decode(InventoryPage.self, from: Data(result.text.utf8))
        XCTAssertEqual(
            page.imageAttachmentIds,
            Array(conversation.messages.flatMap(\.attachments).suffix(10)).map(\.id)
        )
        XCTAssertEqual(page.total, 320)
        let request = try XCTUnwrap(agent.receivedMessages.first)
        XCTAssertEqual(request.map(\.role), [.system, .user])
        XCTAssertEqual(request.last?.content, "Find an earlier image")
        let persisted = try XCTUnwrap(save.savedConversations.last)
        XCTAssertEqual(persisted.contextSummaryCursorMessageId, cursor)
        XCTAssertEqual(persisted.contextSummary, compaction.result?.summary)
        XCTAssertEqual(Array(persisted.messages.prefix(conversation.messages.count)), conversation.messages)
        XCTAssertNil(try loadedState(sut).errorMessage)
        XCTAssertNil(sut.pendingPreflightCompaction)
    }
}

// MARK: - Private

private extension ChatViewModelImageToolsTests {
    func inventoryConversation(imageCount: Int, compacted: Bool) throws -> Conversation {
        let conversationID = UUID()
        let messages = (0..<imageCount).flatMap { index in
            [
                ChatMessage(
                    role: .user, content: "Historical image \(index)",
                    timestamp: Date(timeIntervalSince1970: TimeInterval(index * 2)),
                    attachments: [imageAttachment(conversationId: conversationID, data: nil)]
                ),
                ChatMessage(
                    role: .assistant, content: "Image received, not inspected.",
                    timestamp: Date(timeIntervalSince1970: TimeInterval(index * 2 + 1))
                )
            ]
        }
        let conversation = Conversation(
            id: conversationID, modelId: principal.id,
            contextSummary: compacted ? "Earlier images remain uninspected." : nil,
            contextSummaryCursorMessageId: compacted ? messages.last?.id : nil,
            messages: messages
        )
        return try JSONDecoder().decode(Conversation.self, from: JSONEncoder().encode(conversation))
    }

    func makeInventoryViewModel(
        model: LLMModel, conversation: Conversation, compaction: MockCompactConversationUseCase
    ) -> ChatViewModel {
        // The shared factory owns a fresh compaction mock, so this scenario injects its configured one explicitly.
        ChatViewModel(
            state: .loaded(.init(
                conversation: conversation, messages: conversation.messages,
                selectedModel: model, availableModels: [model, vision, generator],
                modelCatalogScope: settings.getMCPAuthorizationScope()
            )),
            fetchModelsUseCase: MockFetchModelsUseCase(),
            prepareImageAttachmentUseCase: preparation,
            attachmentRepository: attachments,
            streamMessageUseCase: stream,
            generateImageUseCase: nativeGeneration,
            agentStreamUseCase: agent,
            webSearchUseCase: MockWebSearchUseCase(),
            saveConversationUseCase: save,
            getChatPreferencesUseCase: preferences,
            saveSelectedModelUseCase: saveSelectedModel,
            fetchMCPToolsUseCase: MockFetchMCPToolsUseCase(),
            settingsManager: settings,
            getUserProfileContextUseCase: MockGetUserProfileContextUseCase(),
            getMemoryContextUseCase: MockGetMemoryContextUseCase(),
            memoryManager: MockMemoryManager(),
            triggerHapticFeedbackUseCase: MockTriggerHapticFeedbackUseCase(),
            streamingBackgroundUseCase: background,
            notifyStreamingCompletedUseCase: MockNotifyStreamingCompletedUseCase(),
            compactConversationUseCase: compaction,
            imageToolChatRepository: ChatRepository(apiClient: apiClient, attachmentRepository: attachments),
            imageToolGenerationUseCase: specialistGeneration
        )
    }

    @MainActor
    final class InventoryLoads {
        var ids: [UUID] = []
    }
}

private struct InventoryPage: Decodable {
    let imageAttachmentIds: [UUID]
    let offset: Int
    let total: Int
    let nextOffset: Int?

    enum CodingKeys: String, CodingKey {
        case imageAttachmentIds = "image_attachment_ids"
        case offset, total
        case nextOffset = "next_offset"
    }
}
