//
//  ChatViewModelImageContextTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class ChatViewModelImageContextTests: XCTestCase {
    func test_buildRequestContext_withoutVision_projectsBeforeBudgetingLatestTurn() throws {
        // Given
        let model = LLMModel(id: "text", maxInputTokens: 1_000)
        let messages = imageMessages()
        let sut = makeViewModel(model: model, messages: messages)
        let expected = ImageAttachmentContext.messagesForModel(messages, model: model)

        // When
        let context = try sut.buildRequestContext(
            messages: messages, systemPrompt: "", configuration: configuration(model: model)
        )

        // Then
        XCTAssertEqual(context.messages, expected)
        XCTAssertTrue(context.excludedMessages.isEmpty)
        XCTAssertFalse(context.isLatestTurnOverBudget)
        XCTAssertEqual(context.estimatedInputTokens, ContextWindowBuilder().estimatedInputTokens(
            messages: expected, systemPrompt: ""
        ))
        guard case .loaded(let state) = sut.state else { return XCTFail("Expected loaded state") }
        XCTAssertEqual(state.messages, messages)
        XCTAssertEqual(state.conversation?.messages, messages)
    }

    func test_buildRequestContext_nativeVision_keepsImagesAndOriginalBudget() throws {
        // Given
        let model = LLMModel(id: "vision", capabilities: [.vision], maxInputTokens: 10_000)
        let messages = imageMessages()
        let sut = makeViewModel(model: model, messages: messages)

        // When
        let context = try sut.buildRequestContext(
            messages: messages, systemPrompt: "", configuration: configuration(model: model)
        )

        // Then
        XCTAssertEqual(context.messages, messages)
        XCTAssertEqual(context.estimatedInputTokens, ContextWindowBuilder().estimatedInputTokens(
            messages: messages, systemPrompt: ""
        ))
        var smallModel = model
        smallModel.maxInputTokens = 1_000
        XCTAssertThrowsError(try sut.buildRequestContext(
            messages: messages, systemPrompt: "", configuration: configuration(model: smallModel)
        )) { error in
            guard case ChatContextError.latestTurnExceedsContextWindow = error else {
                return XCTFail("Expected latestTurnExceedsContextWindow, got \(error)")
            }
        }
    }

    func test_refreshContextUsage_compactedImageHistory_estimatesProjectedLiveMessagesOnly() throws {
        // Given
        let model = LLMModel(id: "text", maxInputTokens: 1_000)
        let messages = imageMessages() + imageMessages()
        let summary = "Earlier image reference: \(messages[0].attachments[0].id.uuidString); not analyzed."
        let sut = makeViewModel(model: model, messages: messages)
        guard case .loaded(var state) = sut.state else { return XCTFail("Expected loaded state") }
        state.conversation?.contextSummary = summary
        state.conversation?.contextSummaryCursorMessageId = messages[0].id
        let originalConversation = state.conversation
        let expected = ContextWindowBuilder().usage(
            messages: ImageAttachmentContext.messagesForModel(Array(messages.dropFirst()), model: model),
            systemPrompt: "",
            summary: summary,
            model: model,
            compactedMessageCount: 1
        )

        // When
        sut.refreshContextUsage(in: &state)

        // Then
        XCTAssertNotNil(state.contextUsage)
        XCTAssertEqual(state.contextUsage, expected)
        XCTAssertEqual(state.messages, messages)
        XCTAssertEqual(state.conversation, originalConversation)
        let context = try sut.buildRequestContext(
            messages: messages,
            systemPrompt: "",
            configuration: RequestContextConfiguration(
                selectedModel: model, contextWindowTokens: nil,
                summary: summary, summaryCursorMessageId: messages[0].id, tools: []
            )
        )
        XCTAssertEqual(context.compactedMessageCount, 1)
        XCTAssertTrue(context.effectiveSystemPrompt.contains(messages[0].attachments[0].id.uuidString))
        XCTAssertEqual(context.messages.map(\.id), [messages[1].id])
    }

    func test_contextTokensAfterResponse_generatedImage_usesProjectedResponseCost() {
        // Given
        let model = LLMModel(id: "text", maxInputTokens: 10_000)
        let image = imageMessages()[0].attachments[0]
        let assistant = ChatMessage(role: .assistant, content: "Result", attachments: [image])
        let sut = makeViewModel(model: model, messages: [assistant])
        guard case .loaded(let state) = sut.state else { return XCTFail("Expected loaded state") }
        let expectedCost = ContextWindowBuilder().estimatedInputTokens(
            messages: ImageAttachmentContext.messagesForModel([assistant], model: model), systemPrompt: ""
        )

        // When
        let tokens = sut.contextTokensAfterResponse(promptTokens: 100, assistantMessageId: assistant.id, state: state)

        // Then
        XCTAssertEqual(tokens, 100 + expectedCost)
        XCTAssertEqual(state.messages, [assistant])
    }

    // MARK: - Private

    private func imageMessages() -> [ChatMessage] {
        [ChatMessage(role: .user, content: "What is in this image?", attachments: [ChatMessage.Attachment(
            type: .image,
            fileName: "Private.png",
            mimeType: "image/png",
            fileRelativePath: "Attachments/private.png",
            transientData: Data("image bytes".utf8)
        )])]
    }

    private func configuration(model: LLMModel) -> RequestContextConfiguration {
        RequestContextConfiguration(
            selectedModel: model, contextWindowTokens: nil, summary: nil, summaryCursorMessageId: nil, tools: []
        )
    }

    private func makeViewModel(model: LLMModel, messages: [ChatMessage]) -> ChatViewModel {
        ChatViewModel(
            state: .loaded(.init(
                conversation: Conversation(modelId: model.id, messages: messages),
                messages: messages,
                selectedModel: model,
                availableModels: [model]
            )),
            settingsManager: MockSettingsManager(),
            getUserProfileContextUseCase: MockGetUserProfileContextUseCase(),
            getMemoryContextUseCase: MockGetMemoryContextUseCase()
        )
    }
}
