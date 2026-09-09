//
//  GenerateImageUseCase.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 31/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

protocol GenerateImageUseCaseProtocol: Sendable {
    func execute(prompt: String, model: String, attachments: [ChatMessage.Attachment]) async throws -> GeneratedImage
}

struct GenerateImageUseCase: GenerateImageUseCaseProtocol {
    // MARK: - Properties

    private let repository: ImageGenerationRepositoryProtocol
    private let attachmentRepository: AttachmentRepositoryProtocol
    private let prepareImageAttachmentUseCase: PrepareImageAttachmentUseCaseProtocol

    // MARK: - Init

    init(
        repository: ImageGenerationRepositoryProtocol = ImageGenerationRepository(),
        attachmentRepository: AttachmentRepositoryProtocol = AttachmentRepository(),
        prepareImageAttachmentUseCase: PrepareImageAttachmentUseCaseProtocol = PrepareImageAttachmentUseCase(
            preservesGIF: false
        )
    ) {
        self.repository = repository
        self.attachmentRepository = attachmentRepository
        self.prepareImageAttachmentUseCase = prepareImageAttachmentUseCase
    }

    // MARK: - Execute

    func execute(prompt: String, model: String, attachments: [ChatMessage.Attachment]) async throws -> GeneratedImage {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ImageGenerationInputError.promptRequired
        }
        guard attachments.allSatisfy({ $0.type == .image }) else {
            throw ImageGenerationInputError.imagesOnly
        }
        var images: [PreparedImageAttachment] = []
        for (index, attachment) in attachments.enumerated() {
            try Task.checkCancellation()
            let data: Data
            if let transientData = attachment.transientData {
                data = transientData
            } else {
                do {
                    data = try attachmentRepository.load(attachment: attachment)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    throw ImageGenerationInputError.unreadableImage
                }
            }
            try Task.checkCancellation()
            // Inspect the bytes again for restored attachments and use safe multipart filenames.
            let image = try await prepareImageAttachmentUseCase.execute(data: data, fileName: "image-\(index + 1)")
            images.append(image)
        }
        try Task.checkCancellation()
        return try await repository.generateImage(prompt: prompt, model: model, images: images)
    }
}
