//
//  ChatViewModel+ImageTools.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

extension ChatViewModel {
    func makeChatRepository(generatesImages: Bool) -> ChatRepository {
        ChatRepository(
            apiClient: APIClient(
                serverBaseURL: settingsManager.getServerBaseURL(),
                apiKey: settingsManager.getAPIKey(),
                streamTimeoutInterval: generatesImages ? 600 : 60
            ),
            attachmentRepository: attachmentRepository,
            responseModalities: generatesImages ? ["image", "text"] : nil,
            requestTimeoutInterval: generatesImages ? 600 : 60
        )
    }

    func updateImageToolModelNames(registry: ToolRegistry) {
        guard case .loaded(var loadedState) = state else { return }
        let names = Set(registry.definitions.map(\.function.name))
        loadedState.imageToolModelNames = [:]
        if names.contains("analyze_images"), let model = settingsManager.getSelectedVisionModelId() {
            loadedState.imageToolModelNames["analyze_images"] = model
        }
        if names.contains("generate_image"), let model = settingsManager.getSelectedImageGenerationModelId() {
            loadedState.imageToolModelNames["generate_image"] = model
        }
        state = .loaded(loadedState)
    }

    func appendImageTools(
        from loadedState: LoadedState,
        messages: [ChatMessage]?,
        to tools: inout [any ChatToolProtocol]
    ) {
        guard let principal = loadedState.selectedModel,
              principal.capabilities.contains(.functionCalling),
              loadedState.modelCatalogScope == settingsManager.getMCPAuthorizationScope() else { return }
        let client = APIClient(serverBaseURL: settingsManager.getServerBaseURL(), apiKey: settingsManager.getAPIKey())
        let repository = imageToolChatRepository ?? ChatRepository(
            apiClient: client,
            attachmentRepository: attachmentRepository
        )
        let attachments = messages.map { $0.flatMap(\.attachments) }
            ?? (loadedState.messages.flatMap(\.attachments) + loadedState.pendingAttachments)
        if !principal.supportsNativeVision,
           attachments.contains(where: { $0.type == .image }),
           let specialist = loadedState.availableModels.first(where: {
               $0.id == settingsManager.getSelectedVisionModelId() && $0.isVisionSpecialist
           }) {
            tools.append(AnalyzeImagesTool(
                modelId: specialist.id,
                attachments: attachments,
                conversationId: loadedState.conversation?.id ?? loadedState.pendingSessionId,
                chatRepository: repository,
                attachmentRepository: attachmentRepository,
                prepareImageAttachmentUseCase: prepareImageAttachmentUseCase,
                isAvailable: imageToolAvailability(
                    model: specialist, principal: principal, state: loadedState, vision: true
                )
            ))
        }
        if !principal.supportsNativeImageGeneration,
           let specialist = loadedState.availableModels.first(where: {
               $0.id == settingsManager.getSelectedImageGenerationModelId() && $0.isImageGenerationSpecialist
           }) {
            let generation: any GenerateImageUseCaseProtocol = imageToolGenerationUseCase ?? (
                specialist.mode == .imageGeneration
                    ? GenerateImageUseCase(repository: ImageGenerationRepository(apiClient: client))
                        as any GenerateImageUseCaseProtocol
                    : GenerateChatImageUseCase(
                        repository: imageToolChatRepository ?? makeChatRepository(generatesImages: true)
                    )
                        as any GenerateImageUseCaseProtocol
            )
            tools.append(GenerateImageTool(
                modelId: specialist.id,
                generateImageUseCase: generation,
                isAvailable: imageToolAvailability(
                    model: specialist, principal: principal, state: loadedState, vision: false
                )
            ))
        }
    }

    private func imageToolAvailability(
        model: LLMModel,
        principal: LLMModel,
        state snapshot: LoadedState,
        vision: Bool
    ) -> @MainActor @Sendable () -> Bool {
        let scope = snapshot.modelCatalogScope
        let conversationId = snapshot.conversation?.id ?? snapshot.pendingSessionId
        return { [weak self, settingsManager] in
            guard scope == settingsManager.getMCPAuthorizationScope() else { return false }
            let selectedId = vision
                ? settingsManager.getSelectedVisionModelId()
                : settingsManager.getSelectedImageGenerationModelId()
            guard selectedId == model.id else { return false }
            // Definitions are also estimated while the initial loaded state is being constructed.
            guard let self else { return false }
            guard case .loaded(let current) = self.state else { return true }
            guard current.modelCatalogScope == scope,
                  (current.conversation?.id ?? current.pendingSessionId) == conversationId,
                  current.selectedModel?.id == principal.id,
                  current.selectedModel?.capabilities.contains(.functionCalling) == true,
                  let available = current.availableModels.first(where: { $0.id == model.id }) else { return false }
            return vision
                ? available.isVisionSpecialist && current.selectedModel?.supportsNativeVision == false
                : available.isImageGenerationSpecialist && current.selectedModel?.supportsNativeImageGeneration == false
        }
    }
}
