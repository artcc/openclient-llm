//
//  ChatMessage.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

nonisolated struct ChatMessage: Identifiable, Equatable, Sendable, Codable {
    // MARK: - Properties

    let id: UUID
    let role: Role
    var content: String
    var reasoningContent: String?
    let timestamp: Date
    var attachments: [Attachment]
    var tokenUsage: TokenUsage?
    var webSearchResults: [LiteLLMSearchResult]?
    var toolCalls: [ToolCall]?
    var toolCallId: String?
    var toolName: String?
    var isFavourite: Bool
    /// Local per-user-turn reservation, independent of tool transcript delivery.
    var imageGenerationAttempted: Bool?

    enum Role: String, Sendable, Equatable, Codable {
        case user
        case assistant
        case system
        case tool
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        reasoningContent: String? = nil,
        timestamp: Date = Date(),
        attachments: [Attachment] = [],
        tokenUsage: TokenUsage? = nil,
        webSearchResults: [LiteLLMSearchResult]? = nil,
        toolCalls: [ToolCall]? = nil,
        toolCallId: String? = nil,
        toolName: String? = nil,
        isFavourite: Bool = false,
        imageGenerationAttempted: Bool? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoningContent = reasoningContent
        self.timestamp = timestamp
        self.attachments = attachments
        self.tokenUsage = tokenUsage
        self.webSearchResults = webSearchResults
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.isFavourite = isFavourite
        self.imageGenerationAttempted = imageGenerationAttempted
    }

    func hasSameRequestContent(as other: ChatMessage) -> Bool {
        let hasSameAttachments = attachments.elementsEqual(other.attachments) { lhs, rhs in
            lhs.id == rhs.id
                && lhs.type == rhs.type
                && lhs.fileName == rhs.fileName
                && lhs.mimeType == rhs.mimeType
        }
        return id == other.id
            && role == other.role
            && content == other.content
            && hasSameAttachments
            && toolCalls == other.toolCalls
            && toolCallId == other.toolCallId
            && toolName == other.toolName
    }

    // MARK: - Decodable

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(Role.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        reasoningContent = try container.decodeIfPresent(String.self, forKey: .reasoningContent)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        attachments = try container.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        tokenUsage = try container.decodeIfPresent(TokenUsage.self, forKey: .tokenUsage)
        webSearchResults = try container.decodeIfPresent([LiteLLMSearchResult].self, forKey: .webSearchResults)
        toolCalls = try container.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
        toolCallId = try container.decodeIfPresent(String.self, forKey: .toolCallId)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        isFavourite = try container.decodeIfPresent(Bool.self, forKey: .isFavourite) ?? false
        imageGenerationAttempted = try container.decodeIfPresent(Bool.self, forKey: .imageGenerationAttempted)
    }
}

// MARK: - Attachment

extension ChatMessage {
    nonisolated enum AttachmentType: String, Sendable, Equatable, Codable {
        case image
        case pdf
    }

    /// An attachment associated with a chat message.
    ///
    /// Binary data is stored on disk (via `AttachmentRepository`) and referenced here
    /// by `fileRelativePath`. The `data` property loads it from disk on demand and is
    /// intentionally excluded from `Codable` serialisation.
    nonisolated struct Attachment: Identifiable, Equatable, Sendable, Codable {
        // MARK: - Properties

        let id: UUID
        let type: AttachmentType
        let fileName: String
        /// MIME type of the attachment (e.g. `"image/jpeg"`, `"application/pdf"`).
        let mimeType: String
        /// Path relative to `FileManager.documentDirectory`.
        /// e.g. `"Attachments/<conversationId>/<attachmentId>.jpg"`
        /// Empty string indicates a legacy attachment pending migration.
        let fileRelativePath: String
        /// Bytes held only for the lifetime of an ephemeral chat session.
        /// This value is deliberately excluded from Codable persistence.
        let transientData: Data?

        // MARK: - Init

        init(
            id: UUID = UUID(),
            type: AttachmentType,
            fileName: String,
            mimeType: String,
            fileRelativePath: String,
            transientData: Data? = nil
        ) {
            self.id = id
            self.type = type
            self.fileName = fileName
            self.mimeType = mimeType
            self.fileRelativePath = fileRelativePath
            self.transientData = transientData
        }

        // MARK: - Decodable

        /// Custom decoder that tolerates legacy JSON format (pre-v2) where
        /// `fileRelativePath` and `mimeType` were absent and `data` held raw bytes.
        /// Legacy inline bytes are retained in memory until synchronization or migration
        /// has materialized and verified the disk-backed representation.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: ChatMessageAttachmentCodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            let decodedType = try container.decode(AttachmentType.self, forKey: .type)
            type = decodedType
            let decodedFileName = try container.decode(String.self, forKey: .fileName)
            fileName = decodedFileName
            mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
                ?? Self.inferMimeType(for: decodedType, fileName: decodedFileName)
            // Legacy attachments won't have this key; migration will populate it
            fileRelativePath = try container.decodeIfPresent(String.self, forKey: .fileRelativePath) ?? ""
            transientData = try container.decodeIfPresent(Data.self, forKey: .data)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: ChatMessageAttachmentCodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(type, forKey: .type)
            try container.encode(fileName, forKey: .fileName)
            try container.encode(mimeType, forKey: .mimeType)
            try container.encode(fileRelativePath, forKey: .fileRelativePath)
        }

        // MARK: - Helpers

        static func inferMimeType(for type: AttachmentType, fileName: String) -> String {
            switch type {
            case .pdf: return "application/pdf"
            case .image:
                let ext = (fileName as NSString).pathExtension.lowercased()
                switch ext {
                case "png": return "image/png"
                case "gif": return "image/gif"
                case "webp": return "image/webp"
                default: return "image/jpeg"
                }
            }
        }
    }
}

private nonisolated enum ChatMessageAttachmentCodingKeys: String, CodingKey {
    case id
    case type
    case fileName
    case mimeType
    case fileRelativePath
    case data
}

private extension ChatMessage {
    nonisolated enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case reasoningContent
        case timestamp
        case attachments
        case tokenUsage
        case webSearchResults
        case toolCalls
        case toolCallId
        case toolName
        case isFavourite
        case imageGenerationAttempted
    }
}
