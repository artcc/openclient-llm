//
//  ChatViewModelImageGenerationAttemptTests+Restoration.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

extension ChatViewModelImageGenerationAttemptTests {
    func test_send_cancelledBetweenImageAndTranscript_restoresAttemptAndRetainsImageOnRegeneration() async throws {
        // Given
        let persisted = try await cancelAfterImageBeforeSiblingCompletes()
        let restored = try JSONDecoder().decode(Conversation.self, from: JSONEncoder().encode(persisted))
        let attachment = try XCTUnwrap(restored.messages.last?.attachments.first)
        let sut = makeViewModel(conversation: restored)
        XCTAssertEqual(restored.messages.first?.imageGenerationAttempted, true)
        XCTAssertFalse(restored.messages.contains { $0.role == .tool || $0.toolCalls != nil })

        // When
        sut.send(.regenerateLastResponse)
        let task = try XCTUnwrap(sut.streamTask)
        XCTAssertEqual(try loadedState(sut).messages.last?.attachments, [attachment])
        await task.value
        let tool = try generationTool(sut)
        do {
            _ = try await tool.execute(arguments: #"{"prompt":"Another cat"}"#)
            XCTFail("Restored reservation must reject a second request")
        } catch {
            XCTAssertEqual(error as? GenerateImageTool.ExecutionError, .turnLimitReached)
        }

        // Then
        XCTAssertFalse(agent.receivedToolNames.contains("generate_image"))
        XCTAssertEqual(try XCTUnwrap(agent.receivedToolContext).additionalExecutionTime, .zero)
        XCTAssertEqual(generation.executeCallCount, 1)
        XCTAssertEqual(try loadedState(sut).messages.last?.attachments, [attachment])
        XCTAssertEqual(try loadedState(sut).messages.last?.content, "Response")
        XCTAssertEqual(save.savedConversations.last?.messages.last?.attachments, [attachment])
    }

    func test_regenerate_attemptWithoutTranscriptOrImage_doesNotRetryFailedRequest() async throws {
        // Given
        let sut = makeViewModel()
        generation.result = .failure(APIError.invalidResponse)
        let tool = try generationTool(sut)
        do {
            _ = try await tool.execute(arguments: #"{"prompt":"A cat"}"#)
            XCTFail("Expected specialist failure")
        } catch {
            XCTAssertEqual(error as? GenerateImageTool.ExecutionError, .requestFailed)
        }
        let saved = try XCTUnwrap(save.savedConversations.last)
        let restored = try JSONDecoder().decode(Conversation.self, from: JSONEncoder().encode(saved))
        let reloaded = makeViewModel(conversation: restored)

        // When
        try await regenerate(reloaded)

        // Then
        XCTAssertFalse(agent.receivedToolNames.contains("generate_image"))
        XCTAssertEqual(generation.executeCallCount, 1)
        XCTAssertEqual(try loadedState(reloaded).messages.first?.imageGenerationAttempted, true)
        XCTAssertEqual(try loadedState(reloaded).messages.last?.attachments, [])
    }

    func test_send_newUserAfterAttemptWithoutTranscript_getsNewAllowance() async throws {
        // Given
        let sut = makeViewModel(conversation: attemptedConversation())
        let previous = try loadedState(sut).messages

        // When
        sut.send(.inputChanged("Draw a different cat"))
        sut.send(.sendTapped)
        let task = try XCTUnwrap(sut.streamTask)
        await task.value
        let currentUser = try XCTUnwrap(try loadedState(sut).messages.last { $0.role == .user })
        XCTAssertNil(currentUser.imageGenerationAttempted)
        _ = try await generationTool(sut).execute(arguments: #"{"prompt":"Another cat"}"#)

        // Then
        XCTAssertTrue(agent.receivedToolNames.contains("generate_image"))
        XCTAssertEqual(try XCTUnwrap(agent.receivedToolContext).additionalExecutionTime, .seconds(600))
        XCTAssertEqual(generation.executeCallCount, 1)
        XCTAssertEqual(Array(try loadedState(sut).messages.prefix(previous.count)), previous)
        XCTAssertEqual(try loadedState(sut).messages.last { $0.role == .user }?.imageGenerationAttempted, true)
    }

    func test_editMessage_attemptWithoutTranscript_resetsAllowanceForExplicitNewPrompt() async throws {
        // Given
        let conversation = attemptedConversation()
        let userId = try XCTUnwrap(conversation.messages.first?.id)
        let sut = makeViewModel(conversation: conversation)

        // When
        sut.send(.editMessage(id: userId, newContent: "Draw a dog instead"))
        let task = try XCTUnwrap(sut.streamTask)
        XCTAssertNil(try loadedState(sut).messages.first?.imageGenerationAttempted)
        await task.value
        _ = try await generationTool(sut).execute(arguments: #"{"prompt":"A dog"}"#)

        // Then
        XCTAssertTrue(agent.receivedToolNames.contains("generate_image"))
        XCTAssertEqual(generation.executeCallCount, 1)
        XCTAssertEqual(try loadedState(sut).messages.first?.content, "Draw a dog instead")
        XCTAssertEqual(try loadedState(sut).messages.last?.attachments, [])
    }

    func test_regenerate_nativeRestart_clearsAttemptAndDoesNotRepeatedlyTruncateTranscript() async throws {
        // Given
        let native = LLMModel(id: "native", capabilities: [.functionCalling, .imageGeneration])
        let call = ToolCall(
            id: "date", type: "function", function: .init(name: "get_current_datetime", arguments: "{}")
        )
        let transcript = [
            ChatMessage(role: .assistant, content: "", toolCalls: [call]),
            ChatMessage(role: .tool, content: "Today", toolCallId: call.id, toolName: call.function.name)
        ]
        agent.events = [.transcriptAppended(transcript), .generatedImage(image), .completed]
        let sut = makeViewModel(conversation: attemptedConversation(), model: native)

        // When
        try await regenerate(sut)
        let firstImage = try XCTUnwrap(try loadedState(sut).messages.last?.attachments.first)
        XCTAssertNil(try loadedState(sut).messages.first?.imageGenerationAttempted)
        XCTAssertEqual(agent.receivedMessages.first?.filter { $0.role != .system }.map(\.role), [.user])
        agent.events = [.generatedImage(image), .completed]
        try await regenerate(sut)

        // Then
        let state = try loadedState(sut)
        XCTAssertNil(state.messages.first?.imageGenerationAttempted)
        XCTAssertEqual(state.messages.filter { $0.role == .tool }, [transcript[1]])
        XCTAssertEqual(agent.receivedMessages.last?.filter { $0.role == .tool }, [transcript[1]])
        XCTAssertEqual(state.messages.last?.attachments.count, 1)
        XCTAssertNotEqual(state.messages.last?.attachments.first?.id, firstImage.id)
        XCTAssertEqual(generation.executeCallCount, 0)
    }
}

// MARK: - Helpers

private extension ChatViewModelImageGenerationAttemptTests {
    func attemptedConversation() -> Conversation {
        let id = UUID()
        let attachmentId = UUID()
        return Conversation(id: id, modelId: principal.id, messages: [
            ChatMessage(role: .user, content: "Draw a cat", imageGenerationAttempted: true),
            ChatMessage(role: .assistant, content: "", attachments: [.init(
                id: attachmentId, type: .image, fileName: "cat.png", mimeType: "image/png",
                fileRelativePath: "Attachments/\(id)/\(attachmentId).png"
            )])
        ])
    }

    func cancelAfterImageBeforeSiblingCompletes() async throws -> Conversation {
        let gate = AsyncStream<Void>.makeStream()
        defer { gate.continuation.finish() }
        let siblingStarted = expectation(description: "Sibling is waiting")
        let imageSaved = expectation(description: "Image saved without transcript")
        imageSaved.assertForOverFulfill = false
        let repository = parallelGenerationRepository()
        let sut = makeViewModel(
            agentUseCase: AgentStreamUseCase(repository: repository, chunkDelay: .zero),
            search: PendingImageSibling(gate: gate.stream, started: siblingStarted)
        )
        save.executeHandler = { conversation, _ in
            var persisted = conversation
            for index in persisted.messages.indices where !persisted.messages[index].attachments.isEmpty {
                persisted.messages[index].attachments = persisted.messages[index].attachments.map { attachment in
                    ChatMessage.Attachment(
                        id: attachment.id, type: attachment.type, fileName: attachment.fileName,
                        mimeType: attachment.mimeType,
                        fileRelativePath: "Attachments/\(conversation.id)/\(attachment.id).png"
                    )
                }
                XCTAssertEqual(conversation.messages.first?.imageGenerationAttempted, true)
                XCTAssertFalse(conversation.messages.contains { $0.role == .tool || $0.toolCalls != nil })
                imageSaved.fulfill()
            }
            return persisted
        }
        let save = save
        let image = image
        generation.asyncExecuteHandler = { _, _, _ in
            XCTAssertEqual(save.savedConversations.last?.messages.first?.imageGenerationAttempted, true)
            return image
        }
        sut.send(.regenerateLastResponse)
        let task = try XCTUnwrap(sut.streamTask)
        defer { task.cancel() }
        await fulfillment(of: [siblingStarted, imageSaved], timeout: 2)
        sut.send(.stopStreamingTapped)
        gate.continuation.finish()
        await task.value
        _ = await sut.persistenceTask?.value
        XCTAssertEqual(repository.agentCompletionCallCount, 1)
        XCTAssertEqual(generation.executeCallCount, 1)
        XCTAssertNil(try loadedState(sut).errorMessage)
        save.executeHandler = nil
        generation.asyncExecuteHandler = nil
        return try XCTUnwrap(try loadedState(sut).conversation)
    }

    func parallelGenerationRepository() -> MockChatRepository {
        let repository = MockChatRepository()
        repository.agentCompletionResult = .success(ChatCompletionResponse(
            id: "parallel-images", choices: [.init(message: .init(
                role: "assistant", content: nil, reasoningContent: nil, images: nil, toolCalls: [
                    ToolCall(id: "search", type: "function", function: .init(
                        name: "web_search", arguments: #"{"query":"cats"}"#
                    )),
                    ToolCall(id: "image", type: "function", function: .init(
                        name: "generate_image", arguments: #"{"prompt":"A cat"}"#
                    ))
                ]
            ), finishReason: "tool_calls")], usage: nil
        ))
        return repository
    }
}

@MainActor
private struct PendingImageSibling: WebSearchUseCaseProtocol {
    let gate: AsyncStream<Void>
    let started: XCTestExpectation

    func execute(query: String) async throws -> [LiteLLMSearchResult] {
        started.fulfill()
        for await _ in gate { break }
        try Task.checkCancellation()
        throw CancellationError()
    }
}
