//
//  GenerateImageTool.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

/// Reuse across tool rounds and restore the consumed attempt when recreating a tool for an existing turn.
@MainActor
final class GenerateImageTool: ChatToolProtocol {
    // MARK: - Properties

    private let modelId: String
    private let generateImageUseCase: GenerateImageUseCaseProtocol
    private let onAttempt: @MainActor @Sendable () async throws -> Void
    private let isAvailable: @MainActor @Sendable () -> Bool
    private var hasAttemptedGeneration: Bool

    var isAvailableForAdvertisement: Bool { isAvailable() && !hasAttemptedGeneration }

    var definition: ToolDefinition {
        ToolDefinition(
            type: "function",
            function: ToolFunctionDefinition(
                name: "generate_image",
                description: "Generate one new image from a text prompt, at most once per user turn. " +
                    "This tool cannot edit or use existing images. Do not retry after a generation request fails.",
                parameters: ToolParameters(
                    type: "object",
                    properties: [
                        "prompt": ToolParameterProperty(
                            type: "string",
                            description: "A nonempty description of the new image, at most 8000 characters."
                        )
                    ],
                    required: ["prompt"],
                    additionalProperties: .allowed(false)
                )
            )
        )
    }

    // MARK: - Init

    init(
        modelId: String,
        generateImageUseCase: GenerateImageUseCaseProtocol,
        hasAttemptedGeneration: Bool = false,
        onAttempt: @escaping @MainActor @Sendable () async throws -> Void = {},
        isAvailable: @escaping @MainActor @Sendable () -> Bool = { true }
    ) {
        self.modelId = modelId
        self.generateImageUseCase = generateImageUseCase
        self.hasAttemptedGeneration = hasAttemptedGeneration
        self.onAttempt = onAttempt
        self.isAvailable = isAvailable
    }

    // MARK: - Execute

    func execute(arguments: String) async throws -> ToolExecutionResult {
        try checkAvailability()
        guard arguments.utf8.count <= 65_536,
              let input = try? JSONDecoder().decode([String: String].self, from: Data(arguments.utf8)),
              input.count == 1,
              let rawPrompt = input["prompt"] else {
            throw ExecutionError.invalidArguments
        }
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, rawPrompt.count <= 8_000 else { throw ExecutionError.invalidPrompt }
        try checkAvailability()
        guard !hasAttemptedGeneration else { throw ExecutionError.turnLimitReached }
        // Reserve before the first suspension; failures may still have incurred a server-side charge.
        hasAttemptedGeneration = true
        try await onAttempt()
        try checkAvailability()
        let image: GeneratedImage
        do {
            image = try await generateImageUseCase.execute(prompt: prompt, model: modelId, attachments: [])
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            try checkAvailability()
            throw ExecutionError.requestFailed
        }
        try checkAvailability()
        guard !image.data.isEmpty else { throw ExecutionError.requestFailed }
        let model = MCPDisplayText.sanitize(modelId, fallback: "image model", maximumLength: 200)
        return ToolExecutionResult(
            text: String(localized: "Generated one image with model \(model)."),
            images: [image]
        )
    }

    // MARK: - Private

    private func checkAvailability() throws {
        try Task.checkCancellation()
        guard isAvailable() else { throw ExecutionError.unavailable }
    }

    enum ExecutionError: LocalizedError, Equatable {
        case invalidArguments
        case invalidPrompt
        case unavailable
        case turnLimitReached
        case requestFailed

        var errorDescription: String? {
            switch self {
            case .invalidArguments:
                String(localized: "Provide a JSON object containing only a prompt string, within 64 KiB.")
            case .invalidPrompt:
                String(localized: "The image generation prompt must contain between 1 and 8000 characters.")
            case .unavailable:
                String(localized:
                    "Image generation is no longer available. Start a new turn with the current configuration."
                )
            case .turnLimitReached:
                String(localized: "Only one image generation request is allowed per turn. Do not retry in this turn.")
            case .requestFailed:
                String(localized: "Image generation failed. The request cannot be retried in this turn.")
            }
        }
    }
}
