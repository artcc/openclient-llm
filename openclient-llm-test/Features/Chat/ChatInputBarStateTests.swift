//
//  ChatInputBarStateTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 09/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class ChatInputBarStateTests: XCTestCase {
    func test_actions_imageModelWithVision_allowsOnlyImageAttachments() {
        // Given
        let model = LLMModel(id: "image-model", capabilities: [.vision, .functionCalling], mode: .imageGeneration)

        // When
        let state = ChatInputBarState(loadedState: .init(selectedModel: model))

        // Then
        XCTAssertTrue(state.canAttachImages)
        XCTAssertFalse(state.canUseChatActions)
    }

    func test_actions_imageModelWithoutVision_hidesAttachmentsAndChatActions() {
        // Given
        let model = LLMModel(id: "image-model", mode: .imageGeneration)

        // When
        let state = ChatInputBarState(loadedState: .init(selectedModel: model))

        // Then
        XCTAssertFalse(state.canAttachImages)
        XCTAssertFalse(state.canUseChatActions)
    }

    func test_actions_chatModelsAndNoSelection_preserveExistingActions() {
        // Given
        let models: [LLMModel?] = [nil, LLMModel(id: "chat"), LLMModel(id: "vision", capabilities: [.vision])]
        for model in models {
            // When
            let state = ChatInputBarState(loadedState: .init(selectedModel: model))

            // Then
            XCTAssertTrue(state.canAttachImages)
            XCTAssertTrue(state.canUseChatActions)
        }
    }
}
