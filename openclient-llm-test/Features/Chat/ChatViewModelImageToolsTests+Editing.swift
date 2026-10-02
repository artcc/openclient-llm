//
//  ChatViewModelImageToolsTests+Editing.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 01/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

extension ChatViewModelImageToolsTests {
    func test_agentToolDefinitions_editorWithNativeVisionPrincipal_exposesEditingAndInventory() throws {
        // Given
        let editor = LLMModel(id: "editor", capabilities: [.vision], mode: .imageGeneration)
        settings.selectedImageGenerationModelId = editor.id
        settings.selectedVisionModelId = nil
        let sut = makeViewModel(
            model: LLMModel(id: "native-vision", capabilities: [.vision, .functionCalling]),
            pending: [imageAttachment()], extraModels: [editor]
        )

        // When / Then
        XCTAssertEqual(try visualToolNames(sut), ["generate_image", "edit_image", "list_image_attachments"])
        settings.disabledBuiltInTools = [.editImage]
        XCTAssertEqual(try visualToolNames(sut), ["generate_image"])
    }

    func test_agentToolDefinitions_chatSpecialistOrMissingVision_doesNotAdvertiseEditing() throws {
        // Given
        let chatEditor = LLMModel(id: "chat-images", capabilities: [.vision, .imageGeneration])
        let sut = makeViewModel(pending: [imageAttachment()], extraModels: [chatEditor])

        // When / Then
        for model in [generator, chatEditor] {
            settings.selectedImageGenerationModelId = model.id
            XCTAssertFalse(try visualToolNames(sut).contains("edit_image"))
        }
    }

    func test_send_editOnlySpecialist_resolvesCompactedImageAndPersistsSharedAttempt() async throws {
        // Given
        let editor = LLMModel(id: "editor", capabilities: [.vision], mode: .imageGeneration)
        settings.selectedImageGenerationModelId = editor.id
        settings.selectedVisionModelId = nil
        settings.disabledBuiltInTools = [.generateImage]
        let image = imageAttachment()
        let oldUser = ChatMessage(role: .user, content: "Original", attachments: [image])
        let oldAnswer = ChatMessage(role: .assistant, content: "Received")
        let conversation = Conversation(
            modelId: principal.id, contextSummary: "An earlier image is available.",
            contextSummaryCursorMessageId: oldAnswer.id, messages: [oldUser, oldAnswer]
        )
        let sut = makeViewModel(conversation: conversation, extraModels: [editor])
        try await sendMessage(sut, prompt: "Edit the previous image")
        let registry = try capturedRegistry()
        let listing = try await authorizedInvocation(registry, name: "list_image_attachments", arguments: "{}")

        // When
        let page = try await registry.execute(listing)
        let invocation = try await authorizedInvocation(
            registry, name: "edit_image", arguments: editArguments(image.id)
        )
        let result = try await registry.execute(invocation)

        // Then
        XCTAssertTrue(page.text.contains(image.id.uuidString))
        XCTAssertEqual(specialistGeneration.attachments, [[image]])
        XCTAssertEqual(specialistGeneration.models, [editor.id])
        XCTAssertEqual(result.images, [generatedImage])
        XCTAssertEqual(try loadedState(sut).messages.last(where: { $0.role == .user })?.imageGenerationAttempted, true)
        let persistedUser = save.savedConversations.last?.messages.last(where: { $0.role == .user })
        XCTAssertEqual(persistedUser?.imageGenerationAttempted, true)
        XCTAssertFalse(registry.definitions.contains { $0.function.name == "edit_image" })
        XCTAssertEqual(try XCTUnwrap(agent.receivedToolContext).additionalExecutionTime, .seconds(600))
    }

    func test_editImage_disabledAfterAuthorization_doesNotRunSpecialist() async throws {
        // Given
        let editor = LLMModel(id: "editor", capabilities: [.vision], mode: .imageGeneration)
        settings.selectedImageGenerationModelId = editor.id
        let image = imageAttachment()
        let sut = makeViewModel(pending: [image], extraModels: [editor])
        try await sendMessage(sut)
        let registry = try capturedRegistry()
        let invocation = try await authorizedInvocation(
            registry, name: "edit_image", arguments: editArguments(image.id)
        )

        // When
        settings.disabledBuiltInTools = [.editImage]
        _ = try await registry.execute(invocation)

        // Then
        XCTAssertEqual(specialistGeneration.executeCallCount, 0)
        XCTAssertFalse(registry.definitions.contains { $0.function.name == "edit_image" })
    }

    func test_regenerate_restoredEditTranscript_preservesImageAndDoesNotAllowAnotherAttempt() async throws {
        // Given
        let editor = LLMModel(id: "editor", capabilities: [.vision], mode: .imageGeneration)
        settings.selectedImageGenerationModelId = editor.id
        let image = imageAttachment()
        let edited = imageAttachment()
        let call = ToolCall(
            id: "edit-call", type: "function", function: .init(name: "edit_image", arguments: editArguments(image.id))
        )
        let conversation = Conversation(modelId: principal.id, messages: [
            ChatMessage(role: .user, content: "Edit", attachments: [image]),
            ChatMessage(role: .assistant, content: "", toolCalls: [call]),
            ChatMessage(role: .tool, content: "Edited one image", toolCallId: call.id, toolName: "edit_image"),
            ChatMessage(role: .assistant, content: "Done", attachments: [edited])
        ])
        let sut = makeViewModel(conversation: conversation, extraModels: [editor])

        // When
        sut.send(.regenerateLastResponse)
        await sut.streamTask?.value

        // Then
        XCTAssertEqual(try loadedState(sut).messages.last?.attachments, [edited])
        XCTAssertFalse(agent.receivedToolNames.contains("edit_image"))
        XCTAssertFalse(agent.receivedToolNames.contains("generate_image"))
        XCTAssertEqual(specialistGeneration.executeCallCount, 0)
    }

    private func editArguments(_ id: UUID) -> String {
        "{\"prompt\":\"Change the background\",\"attachment_id\":\"\(id.uuidString)\"}"
    }

    func test_regenerate_importedEditWithoutToolName_preservesImageAndConsumedAttempt() async throws {
        // Given
        let editor = LLMModel(id: "editor", capabilities: [.vision], mode: .imageGeneration)
        settings.selectedImageGenerationModelId = editor.id
        let source = imageAttachment()
        let edited = imageAttachment()
        let call = ToolCall(id: "edit", type: "function", function: .init(
            name: "edit_image", arguments: editArguments(source.id)
        ))
        let original = Conversation(modelId: principal.id, messages: [
            ChatMessage(role: .user, content: "Original", attachments: [source]),
            ChatMessage(role: .assistant, content: "Received"),
            ChatMessage(role: .user, content: "Edit the previous image"),
            ChatMessage(role: .assistant, content: "", toolCalls: [call]),
            ChatMessage(role: .tool, content: "Edited", toolCallId: call.id),
            ChatMessage(role: .assistant, content: "Done", attachments: [edited])
        ])
        let data = try ExportConversationsUseCase(attachmentRepository: attachments).execute([original])
        let importedSave = MockSaveConversationUseCase()
        _ = try await ImportConversationsUseCase(
            saveConversationUseCase: importedSave, loadConversationsUseCase: MockLoadConversationsUseCase()
        ).execute(data)
        let restored = try XCTUnwrap(importedSave.savedConversations.first)
        XCTAssertNil(restored.messages.last(where: { $0.role == .user })?.imageGenerationAttempted)
        XCTAssertNil(restored.messages.first(where: { $0.role == .tool })?.toolName)
        let sut = makeViewModel(conversation: restored, extraModels: [editor])

        // When
        sut.send(.regenerateLastResponse)
        await sut.streamTask?.value

        // Then
        XCTAssertEqual(try loadedState(sut).messages.last?.attachments, restored.messages.last?.attachments)
        XCTAssertFalse(agent.receivedToolNames.contains("edit_image"))
        XCTAssertFalse(agent.receivedToolNames.contains("generate_image"))
        var tools: [any ChatToolProtocol] = []
        sut.appendImageTools(from: try loadedState(sut), messages: nil, to: &tools)
        let editing = try XCTUnwrap(tools.compactMap { $0 as? EditImageTool }.first)
        let restoredSource = try XCTUnwrap(restored.messages.first?.attachments.first?.id)
        do {
            _ = try await editing.execute(arguments: editArguments(restoredSource))
            XCTFail("The historical edit must keep its shared attempt consumed")
        } catch {
            XCTAssertEqual(error as? GenerateImageTool.ExecutionError, .turnLimitReached)
        }
        XCTAssertEqual(specialistGeneration.executeCallCount, 0)
    }

    func test_regenerate_historicalEditAfterNativeModelSwitch_preservesTranscriptWithoutNewRequest() async throws {
        let models = [
            LLMModel(id: "dedicated", capabilities: [.vision], mode: .imageGeneration),
            LLMModel(id: "native-chat", capabilities: [.vision, .imageGeneration, .functionCalling])
        ]
        let attempts: [Bool?] = [true, nil]
        for model in models {
            for attempted in attempts {
                // Given
                let image = imageAttachment()
                let result = imageAttachment()
                let call = ToolCall(
                    id: "edit", type: "function",
                    function: .init(name: "edit_image", arguments: editArguments(image.id))
                )
                let conversation = Conversation(modelId: principal.id, messages: [
                    ChatMessage(role: .user, content: "Original", attachments: [image]),
                    ChatMessage(role: .assistant, content: "Received"),
                    ChatMessage(
                        role: .user, content: "Change the previous background", imageGenerationAttempted: attempted
                    ),
                    ChatMessage(role: .assistant, content: "", toolCalls: [call]),
                    ChatMessage(role: .tool, content: "Edited", toolCallId: call.id, toolName: "edit_image"),
                    ChatMessage(role: .assistant, content: "Done", attachments: [result])
                ])
                let sut = makeViewModel(conversation: conversation, extraModels: [model])
                sut.send(.modelSelected(model))
                _ = await sut.persistenceTask?.value
                let before = try loadedState(sut)
                let saveCount = save.executeCallCount

                // When
                sut.send(.regenerateLastResponse)
                await sut.streamTask?.value

                // Then
                let after = try loadedState(sut)
                XCTAssertEqual(after.messages, before.messages)
                XCTAssertEqual(after.conversation, before.conversation)
                XCTAssertNotNil(after.errorMessage)
                XCTAssertFalse(after.isStreaming)
                XCTAssertEqual(save.executeCallCount, saveCount)
                XCTAssertEqual(nativeGeneration.executeCallCount, 0)
                XCTAssertEqual(specialistGeneration.executeCallCount, 0)
                XCTAssertEqual(agent.executeCallCount, 0)
                XCTAssertTrue(stream.receivedMessages.isEmpty)
            }
        }
    }
}
