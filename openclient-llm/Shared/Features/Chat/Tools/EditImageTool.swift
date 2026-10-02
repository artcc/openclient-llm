//
//  EditImageTool.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 01/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

@MainActor
struct EditImageTool: ChatToolProtocol {
    private let attachments: [ChatMessage.Attachment]
    private let conversationId: UUID
    private let executor: GenerateImageTool
    private let isAvailable: @MainActor @Sendable () -> Bool

    var isAvailableForAdvertisement: Bool { isAvailable() && executor.isAvailableForAdvertisement }

    var definition: ToolDefinition {
        ToolDefinition(type: "function", function: ToolFunctionDefinition(
            name: "edit_image",
            description: "Edit one existing image from this conversation using its attachment UUID. " +
                "Use an ID from context or list_image_attachments, never a URL or file path. " +
                "Generation and editing share one attempt per user turn. Never retry a failed image request.",
            parameters: ToolParameters(
                type: "object",
                properties: [
                    "prompt": ToolParameterProperty(
                        type: "string", description: "The requested change, between 1 and 8000 characters."
                    ),
                    "attachment_id": ToolParameterProperty(
                        type: "string", description: "The UUID of the single conversation image to edit."
                    )
                ],
                required: ["prompt", "attachment_id"],
                additionalProperties: .allowed(false)
            )
        ))
    }

    init(
        attachments: [ChatMessage.Attachment],
        conversationId: UUID,
        executor: GenerateImageTool,
        isAvailable: @escaping @MainActor @Sendable () -> Bool
    ) {
        self.attachments = attachments
        self.conversationId = conversationId
        self.executor = executor
        self.isAvailable = isAvailable
    }

    func execute(arguments: String) async throws -> ToolExecutionResult {
        try Task.checkCancellation()
        guard isAvailable() else { throw GenerateImageTool.ExecutionError.unavailable }
        guard arguments.utf8.count <= 65_536,
              let input = try? JSONDecoder().decode([String: String].self, from: Data(arguments.utf8)),
              input.count == 2, let prompt = input["prompt"],
              let reference = input["attachment_id"], let id = UUID(uuidString: reference) else {
            throw ExecutionError.invalidArguments
        }
        let matches = attachments.filter { $0.id == id }
        guard matches.count == 1, let attachment = matches.first, attachment.type == .image else {
            throw ExecutionError.unknownImage
        }
        if attachment.transientData == nil {
            guard (try? ConversationAttachmentPath.key(for: attachment, conversationId: conversationId)) != nil else {
                throw ExecutionError.unknownImage
            }
        }
        return try await executor.executeImageRequest(
            prompt: prompt, attachments: [attachment], isRequestAvailable: isAvailable
        )
    }

    enum ExecutionError: LocalizedError, Equatable {
        case invalidArguments
        case unknownImage

        var errorDescription: String? {
            switch self {
            case .invalidArguments:
                String(localized: "Provide only a prompt and one attachment_id UUID in a JSON object within 64 KiB.")
            case .unknownImage:
                String(localized: "Select one image uniquely available in this conversation.")
            }
        }
    }
}
