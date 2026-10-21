//
//  ChatMessageInterruptionTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 21/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class ChatMessageInterruptionTests: XCTestCase {
    func test_codable_interruption_preservesOptionalStateWithoutChangingRequestContent() throws {
        // Given
        let original = ChatMessage(role: .assistant, content: "Partial")
        for interruption: ChatMessage.ResponseInterruption? in [nil, .backgroundTaskEnded, .unknown] {
            var message = original
            message.responseInterruption = interruption

            // When
            let encoded = try JSONEncoder().encode(message)
            let decoded = try JSONDecoder().decode(ChatMessage.self, from: encoded)

            // Then
            XCTAssertEqual(decoded, message)
            XCTAssertEqual(decoded.isInterruptedResponse, interruption != nil)
            XCTAssertTrue(decoded.hasSameRequestContent(as: original))
            if interruption == nil {
                let text = try XCTUnwrap(String(bytes: encoded, encoding: .utf8))
                XCTAssertFalse(text.contains("responseInterruption"))
            }
        }
    }

    func test_decode_legacyAndFutureInterruption_preservesReadableHistory() throws {
        let legacy = """
        {"id":"00000000-0000-0000-0000-000000000001","role":"assistant","content":"Partial","timestamp":0}
        """
        let future = """
        {"id":"00000000-0000-0000-0000-000000000001","role":"assistant","content":"Partial","timestamp":0,
        "responseInterruption":"futureReason"}
        """
        let legacyMessage = try JSONDecoder().decode(ChatMessage.self, from: Data(legacy.utf8))
        let futureMessage = try JSONDecoder().decode(ChatMessage.self, from: Data(future.utf8))
        XCTAssertNil(legacyMessage.responseInterruption)
        XCTAssertEqual(futureMessage.responseInterruption, .unknown)
        XCTAssertTrue(futureMessage.isInterruptedResponse)
        XCTAssertEqual(futureMessage.content, "Partial")
    }

    func test_messageList_interruptedPlaceholderVisible_keepsToolTranscriptsAndLegacyEmptyMessagesHidden() {
        // Given
        let user = ChatMessage(role: .user, content: "Question")
        let legacy = ChatMessage(role: .assistant, content: "")
        let interrupted = ChatMessage(role: .assistant, content: "", responseInterruption: .backgroundTaskEnded)
        let tool = ChatMessage(role: .tool, content: "Hidden", responseInterruption: .backgroundTaskEnded)
        let toolCall = ChatMessage(role: .assistant, content: "Hidden", toolCalls: [
            ToolCall(id: "call", type: "function", function: .init(name: "lookup", arguments: "{}"))
        ], responseInterruption: .backgroundTaskEnded)
        let state = ChatViewModel.LoadedState(messages: [user, legacy, toolCall, tool, interrupted])

        // When / Then
        XCTAssertEqual(ChatMessageListState(loadedState: state).messages, [user, interrupted])
        XCTAssertFalse(tool.isInterruptedResponse)
        XCTAssertFalse(toolCall.isInterruptedResponse)
        let view = ChatView(viewModel: ChatViewModel(state: .loaded(state), settingsManager: MockSettingsManager()))
        XCTAssertTrue(view.shouldRenderMessage(interrupted, isStreaming: false))
        XCTAssertFalse(view.shouldRenderMessage(legacy, isStreaming: false))
    }

    func test_completionMapping_interruptionMetadata_doesNotBecomeModelContent() throws {
        // Given
        let original = ChatMessage(role: .assistant, content: "Partial")
        var interrupted = original
        interrupted.responseInterruption = .backgroundTaskEnded
        let repository = ChatRepository(apiClient: MockAPIClient(), attachmentRepository: MockAttachmentRepository())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        // When / Then
        XCTAssertEqual(
            try encoder.encode(repository.buildCompletionMessages([original])),
            try encoder.encode(repository.buildCompletionMessages([interrupted]))
        )
    }

    func test_exportImportAndBranch_interruptedResponse_preservesStatusAndRemapsMessageIdentity() async throws {
        // Given
        let message = ChatMessage(role: .assistant, content: "Partial", responseInterruption: .backgroundTaskEnded)
        let conversation = Conversation(modelId: "test", messages: [ChatMessage(role: .user, content: "Ask"), message])
        let save = MockSaveConversationUseCase()
        let export = ExportConversationUseCase(attachmentRepository: MockAttachmentRepository())
        let importer = ImportConversationsUseCase(
            saveConversationUseCase: save, loadConversationsUseCase: MockLoadConversationsUseCase()
        )

        // When
        _ = try await importer.execute(export.execute(conversation))
        let imported = try XCTUnwrap(save.savedConversations.last)
        let branch = try await BranchConversationUseCase(
            saveConversationUseCase: save, attachmentRepository: MockAttachmentRepository()
        ).execute(conversation: imported, fromMessageId: XCTUnwrap(imported.messages.last?.id))

        // Then
        XCTAssertNotEqual(imported.messages.last?.id, message.id)
        XCTAssertEqual(imported.messages.last?.responseInterruption, .backgroundTaskEnded)
        XCTAssertEqual(branch.messages.last?.responseInterruption, .backgroundTaskEnded)
        XCTAssertNotEqual(branch.messages.last?.id, imported.messages.last?.id)
        XCTAssertEqual(branch.messages.last?.content, message.content)
    }
}
