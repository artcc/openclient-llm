//
//  BuiltInTool.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 11/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

enum BuiltInTool: String, CaseIterable, Identifiable, Sendable {
    case currentDatetime = "get_current_datetime"
    case saveMemory = "save_memory"
    case deleteMemory = "delete_memory"
    case webSearch = "web_search"
    case analyzeImages = "analyze_images"
    case listImageAttachments = "list_image_attachments"
    case generateImage = "generate_image"
    case editImage = "edit_image"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .currentDatetime: String(localized: "Current Date and Time")
        case .saveMemory: String(localized: "Save Memory")
        case .deleteMemory: String(localized: "Delete Memory")
        case .webSearch: String(localized: "Search the Web")
        case .analyzeImages: String(localized: "Analyze Images")
        case .listImageAttachments: String(localized: "List Attached Images")
        case .generateImage: String(localized: "Generate an Image")
        case .editImage: String(localized: "Edit an Image")
        }
    }

    var description: String {
        switch self {
        case .currentDatetime:
            String(localized: "Reads the current date, time, and time zone from your device.")
        case .saveMemory:
            String(localized: "Saves facts and preferences for future conversations. Unavailable in Private Chat.")
        case .deleteMemory:
            String(localized: "Removes saved memories when you ask to forget them. Unavailable in Private Chat.")
        case .webSearch:
            String(localized: """
                Searches the web for current information. Requires a configured search service \
                and web search enabled in the chat.
                """)
        case .analyzeImages:
            String(localized: """
                Asks your selected vision model to analyze attached images when the chat model cannot see them.
                """)
        case .listImageAttachments:
            String(localized: """
                Finds references to conversation images for available image analysis or editing tools.
                """)
        case .generateImage:
            String(localized: """
                Uses your selected image generation model to create an image \
                when the chat model cannot generate one itself.
                """)
        case .editImage:
            String(localized: """
                Edits one conversation image with your selected image generation model. Requires a dedicated \
                image model with vision and a chat model without native image generation.
                """)
        }
    }
}
