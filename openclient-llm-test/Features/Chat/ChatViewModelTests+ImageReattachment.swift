//
//  ChatViewModelTests+ImageReattachment.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 01/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
extension ChatViewModelTests {
    func test_send_sharedStoredImageUUID_reattachesFromEachMessageWithoutChangingDisk() async throws {
        try await assertSharedImageReattachment(isPrivate: false)
    }

    func test_send_sharedPrivateImageUUID_reattachesFromEachMessageWithoutWritingDisk() async throws {
        try await assertSharedImageReattachment(isPrivate: true)
    }

    func test_send_reattachRemovedMessage_doesNotSelectSameUUIDFromAnotherMessage() async throws {
        // Given
        let image = ChatMessage.Attachment(
            type: .image, fileName: "photo.jpg", mimeType: "image/jpeg", fileRelativePath: "", transientData: Data([1])
        )
        let removed = ChatMessage(role: .user, content: "", attachments: [image])
        let remaining = ChatMessage(role: .assistant, content: "", attachments: [image])
        sut.state = .loaded(.init(messages: [remaining], selectedModel: LLMModel(id: "chat")))

        // When
        sut.send(.imageReattached(messageId: removed.id, attachmentId: image.id))
        await sut.attachmentPreparationTask?.value

        // Then
        guard case .loaded(let state) = sut.state else { return XCTFail("Expected loaded state") }
        XCTAssertTrue(state.pendingAttachments.isEmpty)
        XCTAssertFalse(state.isPreparingAttachment)
        XCTAssertEqual(state.messages, [remaining])
    }

    private func assertSharedImageReattachment(isPrivate: Bool) async throws {
        // Given
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AttachmentRepository(baseURL: root)
        let bytes = try XCTUnwrap(Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"))
        let source = ChatMessage.Attachment(
            type: .image, fileName: "original.gif", mimeType: "image/gif", fileRelativePath: "",
            transientData: isPrivate ? bytes : nil
        )
        let conversationId = UUID()
        let path = isPrivate ? "" : try repository.save(data: bytes, for: source, conversationId: conversationId)
        let image = ChatMessage.Attachment(
            id: source.id, type: source.type, fileName: source.fileName, mimeType: source.mimeType,
            fileRelativePath: path, transientData: source.transientData
        )
        let messages = [
            ChatMessage(role: .user, content: "Original", attachments: [image]),
            ChatMessage(role: .assistant, content: "Repeated", attachments: [image])
        ]
        let conversation = Conversation(id: conversationId, modelId: "chat", messages: messages)
        sut = ChatViewModel(
            isPrivateChat: isPrivate,
            state: .loaded(.init(conversation: conversation, messages: messages,
                                 inputText: "Keep my draft", selectedModel: LLMModel(id: "chat"))),
            attachmentRepository: repository,
            saveConversationUseCase: mockSaveConversation,
            settingsManager: MockSettingsManager(),
            getUserProfileContextUseCase: mockGetUserProfileContext,
            getMemoryContextUseCase: mockGetMemoryContext
        )
        let originalFiles = try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted()

        // When
        for message in messages {
            sut.send(.imageReattached(messageId: message.id, attachmentId: image.id))
        }
        await sut.attachmentPreparationTask?.value

        // Then
        guard case .loaded(let state) = sut.state else { return XCTFail("Expected loaded state") }
        XCTAssertEqual(state.pendingAttachments.count, 2)
        XCTAssertEqual(Set(state.pendingAttachments.map(\.id)).count, 2)
        XCTAssertTrue(state.pendingAttachments.allSatisfy { $0.id != image.id && $0.fileRelativePath.isEmpty })
        XCTAssertEqual(state.pendingAttachments.compactMap(\.transientData), [bytes, bytes])
        XCTAssertEqual(state.messages, messages)
        XCTAssertEqual(state.inputText, "Keep my draft")
        for attachment in state.pendingAttachments { sut.send(.attachmentRemoved(attachment.id)) }
        XCTAssertEqual(try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted(), originalFiles)
        if !isPrivate { XCTAssertEqual(try repository.load(attachment: image), bytes) }
        XCTAssertTrue(mockSaveConversation.savedConversations.isEmpty)
    }
}
