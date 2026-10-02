//
//  ChatViewModel+Attachments.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 09/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

// MARK: - Attachments

extension ChatViewModel {
    struct ImageInput {
        let fileName: String
        let loadData: @MainActor () async throws -> Data
    }

    enum AttachmentInputValue {
        case text(String)
        case file(Data, String, ChatMessage.AttachmentType)
    }

    struct AttachmentInput {
        let load: @MainActor () async throws -> AttachmentInputValue?
    }

    private enum PreparedInput {
        case text(String)
        case file(Data, String, ChatMessage.AttachmentType, String)
    }

    func addAttachment(data: Data, fileName: String, type: ChatMessage.AttachmentType) {
        switch type {
        case .image:
            prepareImages([ImageInput(fileName: fileName, loadData: { data })])
        case .pdf:
            storeAttachment(data: data, fileName: fileName, type: type, mimeType: "application/pdf")
        }
    }

    func removeAttachment(_ id: UUID) {
        guard case .loaded(var loadedState) = state else { return }
        loadedState.pendingAttachments.removeAll { $0.id == id }
        state = .loaded(loadedState)
    }

    func reattachImage(messageId: UUID, attachmentId: UUID) {
        guard case .loaded(let loadedState) = state,
              !loadedState.isStreaming,
              loadedState.selectedModel?.mode != .imageGeneration
                || loadedState.selectedModel?.supportsNativeVision == true else { return }
        guard let message = loadedState.messages.first(where: { $0.id == messageId }) else { return }
        let matches = message.attachments.filter { $0.id == attachmentId && $0.type == .image }
        guard matches.count == 1, let attachment = matches.first else { return }
        prepareImages([ImageInput(fileName: attachment.fileName) { [attachmentRepository] in
            try attachment.transientData ?? attachmentRepository.load(attachment: attachment)
        }])
    }

    func prepareImages(_ images: [ImageInput]) {
        prepareAttachments(images.map { image in
            AttachmentInput { .file(try await image.loadData(), image.fileName, .image) }
        })
    }

    func prepareAttachments(_ inputs: [AttachmentInput]) {
        guard !inputs.isEmpty, case .loaded(var loadedState) = state else { return }
        let contextId = loadedState.conversation?.id ?? loadedState.pendingSessionId
        let generation = attachmentPreparationGeneration
        attachmentPreparationCount += 1
        loadedState.isPreparingAttachment = true
        state = .loaded(loadedState)
        let previous = attachmentPreparationTask
        attachmentPreparationTask = Task { [weak self, prepareImageAttachmentUseCase] in
            await withTaskCancellationHandler {
                await previous?.value
            } onCancel: {
                previous?.cancel()
            }
            defer { self?.finishPreparingAttachment(generation: generation) }
            for input in inputs {
                guard !Task.isCancelled,
                      self?.isCurrentAttachmentContext(contextId, generation: generation) == true else { return }
                do {
                    let value = try await input.load()
                    try Task.checkCancellation()
                    guard self?.isCurrentAttachmentContext(contextId, generation: generation) == true else { return }
                    guard let value else { continue }
                    let prepared = try await Self.prepareInput(value, using: prepareImageAttachmentUseCase)
                    try Task.checkCancellation()
                    guard self?.isCurrentAttachmentContext(contextId, generation: generation) == true else { return }
                    self?.applyPreparedInput(prepared)
                } catch {
                    guard !Task.isCancelled, !(error is CancellationError) else { return }
                    self?.reportAttachmentPreparationError(contextId: contextId, generation: generation)
                }
            }
        }
    }

    func cancelAttachmentPreparation() {
        let previous = attachmentPreparationTask
        attachmentPreparationTask = nil
        attachmentPreparationGeneration += 1
        attachmentPreparationCount = 0
        previous?.cancel()
        guard case .loaded(var loadedState) = state else { return }
        loadedState.isPreparingAttachment = false
        state = .loaded(loadedState)
    }
}

// MARK: - Private

private extension ChatViewModel {
    private static func prepareInput(
        _ input: AttachmentInputValue,
        using useCase: PrepareImageAttachmentUseCaseProtocol
    ) async throws -> PreparedInput {
        switch input {
        case .text(let text):
            return .text(text)
        case .file(let data, let fileName, .pdf):
            return .file(data, fileName, .pdf, "application/pdf")
        case .file(let data, let fileName, .image):
            let image = try await useCase.execute(data: data, fileName: fileName)
            return .file(image.data, image.fileName, .image, image.mimeType)
        }
    }

    private func applyPreparedInput(_ input: PreparedInput) {
        switch input {
        case .text(let text):
            if !text.isEmpty { send(.inputChanged(text)) }
        case .file(let data, let fileName, let type, let mimeType):
            storeAttachment(data: data, fileName: fileName, type: type, mimeType: mimeType)
        }
    }

    func reportAttachmentPreparationError(contextId: UUID, generation: Int) {
        guard isCurrentAttachmentContext(contextId, generation: generation),
              case .loaded(var loadedState) = state else { return }
        loadedState.errorMessage = String(localized: "An attachment could not be loaded or prepared. Please try again.")
        state = .loaded(loadedState)
        scheduleErrorDismiss()
    }

    func storeAttachment(
        data: Data,
        fileName: String,
        type: ChatMessage.AttachmentType,
        mimeType: String
    ) {
        guard case .loaded(var loadedState) = state else { return }
        let attachment = ChatMessage.Attachment(
            type: type,
            fileName: fileName,
            mimeType: mimeType,
            fileRelativePath: "",
            transientData: data
        )
        loadedState.pendingAttachments.append(attachment)
        state = .loaded(loadedState)
    }

    func finishPreparingAttachment(generation: Int) {
        guard generation == attachmentPreparationGeneration else { return }
        attachmentPreparationCount = max(attachmentPreparationCount - 1, 0)
        guard case .loaded(var loadedState) = state else { return }
        loadedState.isPreparingAttachment = attachmentPreparationCount > 0
        state = .loaded(loadedState)
    }

    func isCurrentAttachmentContext(_ contextId: UUID, generation: Int) -> Bool {
        guard generation == attachmentPreparationGeneration,
              case .loaded(let loadedState) = state else { return false }
        return (loadedState.conversation?.id ?? loadedState.pendingSessionId) == contextId
    }
}
