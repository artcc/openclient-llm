//
//  ChatViewModelImageGenerationAttemptTests+Editing.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 01/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

extension ChatViewModelImageGenerationAttemptTests {
    func test_send_editCancelledBeforeTranscript_restoresOperationAndRejectsNativeRegeneration() async throws {
        // Given
        let saved = try await cancelEditBeforeTranscript()
        let restored = try JSONDecoder().decode(Conversation.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(restored.messages.last(where: { $0.role == .user })?.imageOperationAttempted, .editing)
        XCTAssertFalse(restored.messages.contains { $0.role == .tool || $0.toolCalls != nil })
        XCTAssertEqual(restored.messages.last?.attachments.count, 1)
        let models = [
            LLMModel(id: "dedicated", capabilities: [.vision], mode: .imageGeneration),
            LLMModel(id: "native-chat", capabilities: [.vision, .imageGeneration, .functionCalling])
        ]

        for model in models {
            let sut = makeViewModel(conversation: restored, model: model)
            let before = try loadedState(sut)
            let saveCount = save.executeCallCount

            // When
            sut.send(.regenerateLastResponse)

            // Then
            let after = try loadedState(sut)
            XCTAssertEqual(after.messages, before.messages)
            XCTAssertEqual(after.conversation, before.conversation)
            XCTAssertNotNil(after.errorMessage)
            XCTAssertNil(sut.streamTask)
            XCTAssertEqual(save.executeCallCount, saveCount)
            XCTAssertEqual(generation.executeCallCount, 1)
            XCTAssertEqual(agent.executeCallCount, 0)
        }
    }

    func test_regenerate_legacyUnidentifiedReservation_preservesResultWithoutRequest() throws {
        // Given
        let conversation = Conversation(modelId: principal.id, messages: [
            ChatMessage(role: .user, content: "Change it", imageGenerationAttempted: true),
            ChatMessage(role: .assistant, content: "Done", attachments: [.init(
                type: .image, fileName: "result.png", mimeType: "image/png", fileRelativePath: "",
                transientData: image.data
            )])
        ])
        let sut = makeViewModel(conversation: conversation, model: generator)

        // When
        sut.send(.regenerateLastResponse)

        // Then
        XCTAssertEqual(try loadedState(sut).messages, conversation.messages)
        XCTAssertNil(sut.streamTask)
        XCTAssertEqual(generation.executeCallCount, 0)
        XCTAssertTrue(save.savedConversations.isEmpty)
    }

    private func cancelEditBeforeTranscript() async throws -> Conversation {
        let gate = AsyncStream<Void>.makeStream()
        defer { gate.continuation.finish(); save.executeHandler = nil }
        let siblingStarted = expectation(description: "Sibling waiting")
        let imageSaved = expectation(description: "Edited image persisted before transcript")
        imageSaved.assertForOverFulfill = false
        let source = ChatMessage.Attachment(
            type: .image, fileName: "source.png", mimeType: "image/png", fileRelativePath: "", transientData: Data([9])
        )
        let conversation = Conversation(modelId: principal.id, messages: [
            ChatMessage(role: .user, content: "Original", attachments: [source]),
            ChatMessage(role: .assistant, content: "Received"),
            ChatMessage(role: .user, content: "Change the previous background"),
            ChatMessage(role: .assistant, content: "Pending")
        ])
        let editor = LLMModel(id: "editor", capabilities: [.vision], mode: .imageGeneration)
        settings.selectedImageGenerationModelId = editor.id
        let repository = editingRepository(sourceId: source.id)
        let sut = makeViewModel(
            conversation: conversation,
            agentUseCase: AgentStreamUseCase(repository: repository, chunkDelay: .zero),
            search: EditingSibling(gate: gate.stream, started: siblingStarted), specialist: editor
        )
        save.executeHandler = { conversation, _ in
            if conversation.messages.last?.attachments.isEmpty == false {
                let user = conversation.messages.last(where: { $0.role == .user })
                XCTAssertEqual(user?.imageOperationAttempted, .editing)
                XCTAssertFalse(conversation.messages.contains { $0.role == .tool || $0.toolCalls != nil })
                imageSaved.fulfill()
            }
            return conversation
        }
        sut.send(.regenerateLastResponse)
        let task = try XCTUnwrap(sut.streamTask)
        defer { task.cancel() }
        await fulfillment(of: [siblingStarted, imageSaved], timeout: 2)
        sut.send(.stopStreamingTapped)
        gate.continuation.finish()
        let finished = expectation(description: "Cancelled edit run finished")
        let observer = Task { await task.value; _ = await sut.persistenceTask?.value; finished.fulfill() }
        defer { observer.cancel() }
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(repository.agentCompletionCallCount, 1)
        XCTAssertEqual(generation.executeCallCount, 1)
        return try XCTUnwrap(try loadedState(sut).conversation)
    }

    private func editingRepository(sourceId: UUID) -> MockChatRepository {
        let repository = MockChatRepository()
        let arguments = "{\"prompt\":\"Change background\",\"attachment_id\":\"\(sourceId)\"}"
        repository.agentCompletionResult = .success(ChatCompletionResponse(
            id: "parallel-edit", choices: [.init(message: .init(
                role: "assistant", content: nil, reasoningContent: nil, images: nil, toolCalls: [
                    ToolCall(id: "search", type: "function", function: .init(
                        name: "web_search", arguments: #"{"query":"background"}"#
                    )),
                    ToolCall(id: "edit", type: "function", function: .init(
                        name: "edit_image", arguments: arguments
                    ))
                ]
            ), finishReason: "tool_calls")], usage: nil
        ))
        return repository
    }
}

@MainActor
private struct EditingSibling: WebSearchUseCaseProtocol {
    let gate: AsyncStream<Void>
    let started: XCTestExpectation

    func execute(query: String) async throws -> [LiteLLMSearchResult] {
        started.fulfill()
        for await _ in gate { break }
        throw CancellationError()
    }
}
