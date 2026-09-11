//
//  ImageAttachmentContext.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

nonisolated enum ImageAttachmentContext {
    static func messagesForModel(_ messages: [ChatMessage], model: LLMModel) -> [ChatMessage] {
        guard !model.supportsNativeVision else { return messages }

        return messages.map { message in
            let imageIds = message.attachments.filter { $0.type == .image }.map(\.id)
            guard !imageIds.isEmpty else { return message }

            // Only canonical UUIDs enter this JSON, never attachment names, paths, MIME types, or bytes.
            let references = imageIds.map { "\"\($0.uuidString)\"" }.joined(separator: ",")
            let context = """
            The following image attachments are not directly available to this model and have not been analyzed yet \
            in this message. If analyze_images is available in the current tool definitions, it can analyze these \
            image IDs. Otherwise, explain that you cannot inspect the images directly. Do not infer visual contents \
            from these references; use actual analysis results when present.
            {"image_attachment_ids":[\(references)]}
            """
            var projected = message
            projected.attachments.removeAll { $0.type == .image }
            projected.content = message.content.isEmpty ? context : "\(message.content)\n\n\(context)"
            return projected
        }
    }
}
