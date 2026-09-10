//
//  ImportConversationsUseCase+ImageReferences.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

extension ImportConversationsUseCase {
    struct ImageReferences {
        private let attachmentIds: [UUID: UUID]
        private let conflictingAttachmentIds: [UUID: [UUID: UUID]]
        private let imageIds: [UUID: UUID]
        private let toolNames: [String: Set<String>]

        init(conversation: Conversation, attachmentData: [UUID: [UUID: String]]) {
            var attachmentIds: [UUID: UUID] = [:]
            var imageIds: [UUID: UUID] = [:]
            var toolNames: [String: Set<String>] = [:]
            var payloads: [UUID: Data] = [:]
            var conflictingIds: Set<UUID> = []
            for message in conversation.messages {
                for attachment in message.attachments {
                    guard let payload = attachmentData[message.id]?[attachment.id],
                          let data = Data(base64Encoded: payload) else { continue }
                    if let previous = payloads[attachment.id], previous != data {
                        conflictingIds.insert(attachment.id)
                    }
                    payloads[attachment.id] = data
                    // Version 1 allows repeated attachment IDs; retain that shared identity, not a last-match alias.
                    let newId = attachmentIds[attachment.id] ?? UUID()
                    attachmentIds[attachment.id] = newId
                    if attachment.type == .image {
                        imageIds[attachment.id] = newId
                    }
                }
                if message.role == .assistant {
                    for call in message.toolCalls ?? [] {
                        toolNames[call.id, default: []].insert(call.function.name)
                    }
                }
            }
            self.attachmentIds = attachmentIds
            self.imageIds = imageIds.filter { !conflictingIds.contains($0.key) }
            self.toolNames = toolNames
            // Conflicting bytes cannot share a persisted path. Do not arbitrarily retarget their ambiguous references.
            self.conflictingAttachmentIds = conversation.messages.reduce(into: [:]) { ids, message in
                for attachment in message.attachments where conflictingIds.contains(attachment.id) {
                    if ids[message.id]?[attachment.id] == nil {
                        ids[message.id, default: [:]][attachment.id] = UUID()
                    }
                }
            }
        }

        func attachmentId(for originalId: UUID, messageId: UUID) -> UUID? {
            conflictingAttachmentIds[messageId]?[originalId] ?? attachmentIds[originalId]
        }

        func remapText(_ text: String) -> String {
            guard !imageIds.isEmpty else { return text }
            // Match whole UUID references, not identifiers, filenames, or path components containing one.
            let pattern = #"(?<![\p{L}\p{N}_/\\.\-])[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}"#
                + #"(?![\p{L}\p{N}_/\\\-]|\.[\p{L}\p{N}_])"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                return text
            }
            var result = text
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                guard let range = Range(match.range, in: result),
                      let oldId = UUID(uuidString: String(result[range])),
                      let newId = imageIds[oldId] else { continue }
                result.replaceSubrange(range, with: newId.uuidString)
            }
            return result
        }

        func remapContent(of message: ChatMessage) -> String {
            switch message.role {
            case .assistant:
                return remapText(message.content)
            case .tool:
                var name = message.toolName
                if name == nil, let callId = message.toolCallId,
                   let names = toolNames[callId], names.count == 1 {
                    name = names.first
                }
                switch name {
                case "list_image_attachments":
                    return remapJSON(message.content, idsKey: "image_attachment_ids")
                case "analyze_images":
                    return remapAnalysis(message.content)
                default:
                    return message.content
                }
            case .user, .system:
                return message.content
            }
        }

        func remapToolCall(_ call: ToolCall) -> ToolCall {
            guard call.function.name == "analyze_images" else { return call }
            return ToolCall(
                id: call.id,
                type: call.type,
                function: ToolCallFunction(
                    name: call.function.name,
                    arguments: remapJSON(call.function.arguments, idsKey: "attachment_ids", textKey: "question")
                )
            )
        }

        private func remapAnalysis(_ text: String, depth: Int = 0) -> String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") || trimmed.hasPrefix("\"") {
                // Decode each recognized envelope before matching UUID boundaries in its plain-text payload.
                guard depth < 8 else { return text }
                return remapJSON(text, textKey: "untrustedExternalToolResult", analysisDepth: depth + 1)
            }
            return remapText(text)
        }

        private func remapJSON(
            _ text: String,
            idsKey: String? = nil,
            textKey: String? = nil,
            analysisDepth: Int? = nil
        ) -> String {
            guard !imageIds.isEmpty else { return text }
            var scanner = ImportImageReferenceJSONScanner(text: text, idsKey: idsKey, textKey: textKey)
            return (try? scanner.transform { key, value in
                if key == idsKey {
                    guard let oldId = UUID(uuidString: value), let newId = imageIds[oldId] else { return value }
                    return newId.uuidString
                }
                if let analysisDepth {
                    return remapAnalysis(value, depth: analysisDepth)
                }
                return remapText(value)
            }) ?? text
        }
    }
}
