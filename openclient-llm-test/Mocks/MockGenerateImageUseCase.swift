//
//  MockGenerateImageUseCase.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 09/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation
@testable import openclient_llm

// Safety: Only used within serialized @MainActor test methods.
final class MockGenerateImageUseCase: GenerateImageUseCaseProtocol, @unchecked Sendable {
    // MARK: - Properties

    var result: Result<GeneratedImage, Error> = .failure(APIError.invalidResponse)
    var prompts: [String] = []
    var models: [String] = []
    var attachments: [[ChatMessage.Attachment]] = []
    var asyncExecuteHandler: ((String, String, Int) async throws -> GeneratedImage)?
    private(set) var executeCallCount = 0

    // MARK: - Execute

    func execute(prompt: String, model: String, attachments: [ChatMessage.Attachment]) async throws -> GeneratedImage {
        executeCallCount += 1
        prompts.append(prompt)
        models.append(model)
        self.attachments.append(attachments)
        if let asyncExecuteHandler {
            return try await asyncExecuteHandler(prompt, model, executeCallCount)
        }
        return try result.get()
    }
}
