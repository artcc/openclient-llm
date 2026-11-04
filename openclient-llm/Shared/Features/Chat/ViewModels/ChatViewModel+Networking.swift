//
//  ChatViewModel+Networking.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 04/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

extension ChatViewModel.LoadedState {
    var chatID: UUID { conversation?.id ?? pendingSessionId }
}

extension ChatViewModel {
    func makeChatAPIClient(chatID: UUID, streamTimeoutInterval: TimeInterval = 60) -> APIClient {
        APIClient(
            serverBaseURL: settingsManager.getServerBaseURL(),
            apiKey: settingsManager.getAPIKey(),
            customHeaders: settingsManager.getCustomHeaders(),
            chatIDHeaderName: settingsManager.getChatIDHeaderName(),
            chatID: chatID,
            streamTimeoutInterval: streamTimeoutInterval
        )
    }

    func makeChatRepository(chatID: UUID, generatesImages: Bool = false) -> ChatRepository {
        ChatRepository(
            apiClient: makeChatAPIClient(chatID: chatID, streamTimeoutInterval: generatesImages ? 600 : 60),
            attachmentRepository: attachmentRepository,
            responseModalities: generatesImages ? ["image", "text"] : nil,
            requestTimeoutInterval: generatesImages ? 600 : 60
        )
    }

    func makeImageGenerationUseCase(chatID: UUID) -> any GenerateImageUseCaseProtocol {
        generateImageUseCase ?? GenerateImageUseCase(
            repository: ImageGenerationRepository(apiClient: makeChatAPIClient(chatID: chatID)),
            attachmentRepository: attachmentRepository
        )
    }

    func makeCompactionUseCase(chatID: UUID) -> any CompactConversationUseCaseProtocol {
        compactConversationUseCase ?? CompactConversationUseCase(
            repository: makeChatRepository(chatID: chatID), attachmentRepository: attachmentRepository
        )
    }
}
