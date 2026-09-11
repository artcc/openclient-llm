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
                Finds references to images attached to the conversation for image analysis. \
                Requires a selected vision model when the chat model cannot see images.
                """)
        case .generateImage:
            String(localized: """
                Uses your selected image generation model to create an image \
                when the chat model cannot generate one itself.
                """)
        }
    }
}
