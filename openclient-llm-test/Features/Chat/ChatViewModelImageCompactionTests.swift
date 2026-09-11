//
//  ChatViewModelImageCompactionTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class ChatViewModelImageCompactionTests: XCTestCase {
    func test_prepareRequestContext_withoutVision_compactsProjectionButPersistsOriginalHistory() async throws {
        // Given
        let compaction = RecordingImageCompactionUseCase()
        let save = MockSaveConversationUseCase()
        let (sut, sendContext) = makeScenario(compaction: compaction, save: save)
        guard case .loaded(let originalState) = sut.state else { return XCTFail("Expected loaded state") }
        let expected = ImageAttachmentContext.messagesForModel(sendContext.messages, model: sendContext.selectedModel)

        // When
        let context = try await sut.prepareRequestContext(for: sendContext, systemPrompt: "", tools: [])

        // Then
        XCTAssertEqual(compaction.receivedMessages, [expected])
        XCTAssertEqual(compaction.receivedMessages[0].map(\.id), sendContext.messages.map(\.id))
        XCTAssertEqual(compaction.receivedMessages[0][0].attachments, [sendContext.messages[0].attachments[1]])
        XCTAssertFalse(compaction.receivedMessages[0].flatMap(\.attachments).contains { $0.type == .image })
        XCTAssertEqual(context.messages, [expected[2]])
        XCTAssertEqual(context.compactedMessageCount, 2)
        XCTAssertTrue(context.effectiveSystemPrompt.contains(sendContext.messages[0].attachments[0].id.uuidString))
        let persisted = try XCTUnwrap(save.savedConversations.first)
        XCTAssertEqual(persisted.messages, originalState.messages)
        XCTAssertEqual(persisted.contextSummaryCursorMessageId, sendContext.messages[1].id)
        XCTAssertEqual(persisted.messages[0].attachments[0].transientData, Data("image bytes".utf8))
        guard case .loaded(let finalState) = sut.state else { return XCTFail("Expected loaded state") }
        XCTAssertEqual(finalState.messages, originalState.messages)
        XCTAssertNil(sut.pendingPreflightCompaction)
    }

    func test_prepareRequestContext_nativeVision_compactionReceivesOriginalAttachments() async throws {
        // Given
        let compaction = RecordingImageCompactionUseCase()
        let save = MockSaveConversationUseCase()
        let (sut, sendContext) = makeScenario(capabilities: [.vision], compaction: compaction, save: save)

        // When
        let context = try await sut.prepareRequestContext(for: sendContext, systemPrompt: "", tools: [])

        // Then
        XCTAssertEqual(compaction.receivedMessages, [sendContext.messages])
        XCTAssertEqual(context.messages, [sendContext.messages[2]])
        XCTAssertEqual(context.messages[0].attachments[0].transientData, Data("image bytes".utf8))
        XCTAssertEqual(save.savedConversations.first?.messages.prefix(3), sendContext.messages.prefix(3))
    }

    func test_prepareRequestContext_attachmentRenamedDuringCompaction_rejectsStaleOriginalBeforeSaving() async {
        // Given
        let compaction = RecordingImageCompactionUseCase()
        let save = MockSaveConversationUseCase()
        let (sut, sendContext) = makeScenario(compaction: compaction, save: save)
        compaction.onExecute = { [weak sut] in
            guard let sut else { return }
            self.renameFirstImage(in: sut)
        }

        // When
        do {
            _ = try await sut.prepareRequestContext(for: sendContext, systemPrompt: "", tools: [])
            XCTFail("Expected cancellation for changed original attachment metadata")
        } catch is CancellationError {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        // Then
        XCTAssertEqual(compaction.receivedMessages.count, 1)
        XCTAssertTrue(save.savedConversations.isEmpty)
        guard case .loaded(let state) = sut.state else { return XCTFail("Expected loaded state") }
        XCTAssertEqual(state.messages[0].attachments[0].fileName, "Renamed.png")
        XCTAssertNil(state.conversation?.contextSummary)
    }

    func test_prepareRequestContext_attachmentRenamedDuringPersistence_rejectsStaleOriginalAfterSaving() async {
        // Given
        let compaction = RecordingImageCompactionUseCase()
        let save = MockSaveConversationUseCase()
        let (sut, sendContext) = makeScenario(compaction: compaction, save: save)
        save.executeHandler = { [weak sut] conversation, _ in
            if let sut { self.renameFirstImage(in: sut) }
            return conversation
        }

        // When
        do {
            _ = try await sut.prepareRequestContext(for: sendContext, systemPrompt: "", tools: [])
            XCTFail("Expected cancellation for changed original attachment metadata")
        } catch is CancellationError {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        // Then
        XCTAssertEqual(save.savedConversations.count, 1)
        guard case .loaded(let state) = sut.state else { return XCTFail("Expected loaded state") }
        XCTAssertEqual(state.messages[0].attachments[0].fileName, "Renamed.png")
        XCTAssertNil(sut.pendingPreflightCompaction)
    }

    // MARK: - Private

    private func makeScenario(
        capabilities: [LLMModel.Capability] = [],
        compaction: RecordingImageCompactionUseCase,
        save: MockSaveConversationUseCase
    ) -> (ChatViewModel, ChatViewModel.SendMessageContext) {
        let model = LLMModel(id: "test", capabilities: capabilities, maxInputTokens: 2_000)
        let image = ChatMessage.Attachment(
            type: .image, fileName: "Private.png", mimeType: "image/png",
            fileRelativePath: "Attachments/private.png", transientData: Data("image bytes".utf8)
        )
        let document = ChatMessage.Attachment(
            type: .pdf, fileName: "Original.pdf", mimeType: "application/pdf",
            fileRelativePath: "Attachments/original.pdf", transientData: Data("document bytes".utf8)
        )
        let messages = [
            ChatMessage(role: .user, content: String(repeating: "u", count: 7_000), attachments: [image, document]),
            ChatMessage(role: .assistant, content: "Earlier answer"),
            ChatMessage(role: .user, content: "Latest question", attachments: [image])
        ]
        let assistant = ChatMessage(role: .assistant, content: "")
        let conversation = Conversation(modelId: model.id, messages: messages)
        compaction.result = CompactedConversation(
            summary: "Image reference: \(image.id.uuidString); not analyzed.", cursorMessageId: messages[1].id
        )
        let sut = ChatViewModel(
            state: .loaded(.init(
                conversation: conversation, messages: messages + [assistant],
                selectedModel: model, availableModels: [model]
            )),
            saveConversationUseCase: save,
            settingsManager: MockSettingsManager(),
            getUserProfileContextUseCase: MockGetUserProfileContextUseCase(),
            getMemoryContextUseCase: MockGetMemoryContextUseCase(),
            compactConversationUseCase: compaction
        )
        sut.activeAssistantMessageId = assistant.id
        let context = ChatViewModel.SendMessageContext(
            text: "Latest question", messages: messages, modelId: model.id, assistantId: assistant.id,
            systemPrompt: "", parameters: ModelParameters(), webSearchEnabled: false,
            modelCapabilities: model.capabilities, selectedModel: model, contextWindowTokens: nil,
            contextSummary: nil, contextSummaryCursorMessageId: nil
        )
        return (sut, context)
    }

    private func renameFirstImage(in sut: ChatViewModel) {
        guard case .loaded(var state) = sut.state else { return XCTFail("Expected loaded state") }
        let original = state.messages[0].attachments[0]
        state.messages[0].attachments[0] = ChatMessage.Attachment(
            id: original.id, type: original.type, fileName: "Renamed.png", mimeType: original.mimeType,
            fileRelativePath: original.fileRelativePath, transientData: original.transientData
        )
        sut.state = .loaded(state)
    }
}

// Safety: Only used within serialized @MainActor test methods.
private final class RecordingImageCompactionUseCase: CompactConversationUseCaseProtocol, @unchecked Sendable {
    var receivedMessages: [[ChatMessage]] = []
    var result: CompactedConversation?
    var onExecute: (() -> Void)?

    func execute(
        messages: [ChatMessage], configuration: CompactionConfiguration
    ) async throws -> CompactedConversation? {
        receivedMessages.append(messages)
        onExecute?()
        return result
    }
}
