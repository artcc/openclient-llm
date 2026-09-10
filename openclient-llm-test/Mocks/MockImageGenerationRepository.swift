//
//  MockImageGenerationRepository.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 09/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation
@testable import openclient_llm

@MainActor
final class MockImageGenerationRepository: ImageGenerationRepositoryProtocol {
    var result: Result<GeneratedImage, Error> = .failure(APIError.invalidResponse)
    private(set) var generateImageCallCount = 0
    private(set) var lastPrompt: String?
    private(set) var lastModel: String?
    private(set) var lastImages: [PreparedImageAttachment]?

    func generateImage(
        prompt: String,
        model: String,
        images: [PreparedImageAttachment]
    ) async throws -> GeneratedImage {
        generateImageCallCount += 1
        lastPrompt = prompt
        lastModel = model
        lastImages = images
        return try result.get()
    }
}
