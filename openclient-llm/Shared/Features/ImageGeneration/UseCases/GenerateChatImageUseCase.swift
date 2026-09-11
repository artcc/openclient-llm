//
//  GenerateChatImageUseCase.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

struct GenerateChatImageUseCase: GenerateImageUseCaseProtocol {
    // MARK: - Properties

    private let repository: ChatRepositoryProtocol

    // MARK: - Init

    init(repository: ChatRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Execute

    func execute(prompt: String, model: String, attachments: [ChatMessage.Attachment]) async throws -> GeneratedImage {
        try Task.checkCancellation()
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ImageGenerationInputError.promptRequired
        }
        guard attachments.isEmpty else { throw ImageGenerationInputError.textOnly }
        let stream = repository.streamMessage(
            messages: [ChatMessage(role: .user, content: prompt)],
            model: model,
            parameters: .default
        )
        for try await chunk in stream {
            try Task.checkCancellation()
            if case .image(let data) = chunk {
                return try GeneratedImageDecoder.decode(data: data)
            }
        }
        try Task.checkCancellation()
        throw APIError.invalidResponse
    }
}
