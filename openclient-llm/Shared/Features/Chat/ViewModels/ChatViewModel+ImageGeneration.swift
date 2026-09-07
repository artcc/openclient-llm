//
//  ChatViewModel+ImageGeneration.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 09/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

// MARK: - Image Generation

extension ChatViewModel {
    func performImageGeneration(_ context: SendMessageContext) async {
        let assistantMessageId = context.assistantId
        streamingBackgroundUseCase.update(.generatingImage)
        do {
            let generatedImage = try await generateImageUseCase.execute(
                prompt: context.text,
                model: context.modelId
            )
            try Task.checkCancellation()
            guard isActiveStream(assistantMessageId),
                  case .loaded(var currentState) = state,
                  let index = currentState.messages.firstIndex(where: { $0.id == assistantMessageId }) else { return }
            guard let attachment = generatedImageAttachment(
                data: generatedImage.data,
                mimeType: generatedImage.mimeType,
                state: currentState
            ) else { throw APIError.invalidResponse }

            currentState.messages[index].attachments.append(attachment)
            currentState.isStreaming = false
            state = .loaded(currentState)
            LogManager.success("performImageGeneration completed model=\(context.modelId)")
            streamingBackgroundUseCase.update(.saving)
            let didPersist = await persistConversation()
            guard !Task.isCancelled, isActiveStream(assistantMessageId) else { return }
            let didComplete = isPrivateChat || didPersist
            if didComplete, streamingBackgroundUseCase.shouldSendCompletionNotification {
                notifyStreamingCompletedUseCase.execute()
            }
            if !didComplete { scheduleConversationPersistence() }
            streamingBackgroundUseCase.end(success: didComplete)
            completeActiveStream(assistantMessageId)
        } catch is CancellationError {
            return
        } catch {
            guard isActiveStream(assistantMessageId),
                  case .loaded(var currentState) = state else { return }
            LogManager.error("performImageGeneration error model=\(context.modelId): \(error)")
            if let index = currentState.messages.firstIndex(where: { $0.id == assistantMessageId }),
               currentState.messages[index].attachments.isEmpty {
                currentState.messages.remove(at: index)
            }
            currentState.isStreaming = false
            currentState.errorMessage = error.localizedDescription
            state = .loaded(currentState)
            scheduleErrorDismiss()
            streamingBackgroundUseCase.update(.saving)
            await persistConversation()
            guard !Task.isCancelled, isActiveStream(assistantMessageId) else { return }
            streamingBackgroundUseCase.end(success: false)
            completeActiveStream(assistantMessageId)
        }
    }
}
