//
//  ImageGenerationInputError.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 09/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

nonisolated enum ImageGenerationInputError: LocalizedError {
    case promptRequired
    case visionRequired
    case imagesOnly
    case unreadableImage
    case textOnly

    var errorDescription: String? {
        switch self {
        case .promptRequired:
            String(localized: "Image generation requires a text prompt.")
        case .visionRequired:
            String(localized: "This image generation model does not support image attachments.")
        case .imagesOnly:
            String(localized: "Image generation only supports image attachments.")
        case .unreadableImage:
            String(localized: "An attached image could not be loaded. Please attach it again.")
        case .textOnly:
            String(localized: "Chat image generation currently supports text prompts only.")
        }
    }
}
