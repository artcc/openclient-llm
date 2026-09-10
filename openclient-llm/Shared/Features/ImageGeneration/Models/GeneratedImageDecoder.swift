//
//  GeneratedImageDecoder.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum GeneratedImageDecoder {
    static let maximumBytes = 25 * 1_024 * 1_024

    static func decode(dataURL: String) throws -> GeneratedImage {
        let maximumEncodedBytes = ((maximumBytes + 2) / 3) * 4
        guard dataURL.utf8.count <= maximumEncodedBytes + 128,
              let comma = dataURL.firstIndex(of: ",") else { throw APIError.invalidResponse }
        let header = dataURL[..<comma]
        guard header.hasPrefix("data:image/"), header.hasSuffix(";base64") else {
            throw APIError.invalidResponse
        }
        let encoded = dataURL[dataURL.index(after: comma)...]
        let count = encoded.utf8.count
        let padding = encoded.hasSuffix("==") ? 2 : (encoded.hasSuffix("=") ? 1 : 0)
        // Bound decoded allocation before constructing Data, including the final padded quartet.
        guard count > 0, count <= maximumEncodedBytes, count.isMultiple(of: 4),
              count / 4 * 3 - padding <= maximumBytes,
              let data = Data(base64Encoded: String(encoded)) else { throw APIError.invalidResponse }
        return try decode(data: data)
    }

    static func decode(data: Data) throws -> GeneratedImage {
        guard !data.isEmpty, data.count <= maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let identifier = CGImageSourceGetType(source),
              let type = UTType(identifier as String), type.conforms(to: .image),
              let mimeType = type.preferredMIMEType else { throw APIError.invalidResponse }
        return GeneratedImage(data: data, mimeType: mimeType, revisedPrompt: nil)
    }
}
