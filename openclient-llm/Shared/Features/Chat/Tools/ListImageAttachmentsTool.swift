//
//  ListImageAttachmentsTool.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

struct ListImageAttachmentsTool: ChatToolProtocol {
    private let attachmentIds: [UUID]
    private let isAvailable: @MainActor @Sendable () -> Bool

    var isAvailableForAdvertisement: Bool { isAvailable() }

    var definition: ToolDefinition {
        ToolDefinition(
            type: "function",
            function: ToolFunctionDefinition(
                name: "list_image_attachments",
                description: "Find image attachment UUIDs from this conversation, including compacted history. " +
                    "Returns up to 10 IDs in chronological attachment order, total count, " +
                    "and next_offset if more exist. " +
                    "Use only when the image IDs you need are missing from context, then call analyze_images.",
                parameters: ToolParameters(
                    type: "object",
                    properties: [
                        "offset": ToolParameterProperty(
                            type: "integer",
                            description: "Zero-based offset in the image inventory, starting at 0 when omitted."
                        )
                    ],
                    required: [],
                    additionalProperties: .allowed(false)
                )
            )
        )
    }

    init(
        attachments: [ChatMessage.Attachment],
        isAvailable: @escaping @MainActor @Sendable () -> Bool
    ) {
        attachmentIds = attachments.filter { $0.type == .image }.map(\.id)
        self.isAvailable = isAvailable
    }

    func execute(arguments: String) async throws -> ToolExecutionResult {
        try Task.checkCancellation()
        guard isAvailable() else { throw AnalyzeImagesTool.ExecutionError.unavailable }
        guard arguments.utf8.count <= 1_024,
              let input = try? JSONDecoder().decode([String: Int].self, from: Data(arguments.utf8)),
              input.keys.allSatisfy({ $0 == "offset" }) else { throw ExecutionError.invalidOffset }
        let offset = input["offset"] ?? 0
        guard (0...attachmentIds.count).contains(offset) else { throw ExecutionError.invalidOffset }
        let end = offset + min(10, attachmentIds.count - offset)
        let page = ImageAttachmentPage(
            imageAttachmentIds: Array(attachmentIds[offset..<end]),
            offset: offset,
            total: attachmentIds.count,
            nextOffset: end < attachmentIds.count ? end : nil
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let text = String(data: try encoder.encode(page), encoding: .utf8) else {
            throw APIError.invalidResponse
        }
        return ToolExecutionResult(text: text)
    }

    enum ExecutionError: LocalizedError {
        case invalidOffset

        var errorDescription: String? {
            String(localized: "Provide a JSON object with an optional integer offset within the image inventory.")
        }
    }
}

private nonisolated struct ImageAttachmentPage: Encodable {
    let imageAttachmentIds: [UUID]
    let offset: Int
    let total: Int
    let nextOffset: Int?
}
