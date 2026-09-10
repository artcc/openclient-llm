//
//  ImageGenerationRequest.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 31/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

nonisolated struct ImageGenerationRequest: Encodable, Sendable {
    let model: String
    let prompt: String
    let numberOfImages: Int
    let responseFormat: String

    enum CodingKeys: String, CodingKey {
        case model
        case prompt
        case numberOfImages = "n"
        case responseFormat = "response_format"
    }
}
