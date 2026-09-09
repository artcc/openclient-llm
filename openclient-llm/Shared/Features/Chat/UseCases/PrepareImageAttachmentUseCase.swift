//
//  PrepareImageAttachmentUseCase.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 09/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated struct PreparedImageAttachment: Equatable, Sendable {
    let data: Data
    let fileName: String
    let mimeType: String
}

nonisolated enum ImageAttachmentConstraints {
    static let maximumBytes = 5_000_000
}

protocol PrepareImageAttachmentUseCaseProtocol: Sendable {
    @concurrent
    func execute(data: Data, fileName: String) async throws -> PreparedImageAttachment
}

nonisolated struct PrepareImageAttachmentUseCase: PrepareImageAttachmentUseCaseProtocol {
    // MARK: - Properties

    private let preservesGIF: Bool

    // MARK: - Init

    init(preservesGIF: Bool = true) {
        self.preservesGIF = preservesGIF
    }

    // MARK: - Execute

    @concurrent
    func execute(data: Data, fileName: String) async throws -> PreparedImageAttachment {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let typeIdentifier = CGImageSourceGetType(source),
              let sourceType = UTType(typeIdentifier as String) else {
            throw PrepareImageAttachmentError.invalidImage
        }

        if let supportedFormat = supportedFormat(for: sourceType),
           data.count <= ImageAttachmentConstraints.maximumBytes {
            return PreparedImageAttachment(
                data: data,
                fileName: normalizedFileName(fileName, extension: supportedFormat.fileExtension),
                mimeType: supportedFormat.mimeType
            )
        }

        return try convertToJPEG(source: source, fileName: fileName)
    }
}

// MARK: - Private

private extension PrepareImageAttachmentUseCase {
    struct SupportedFormat {
        let fileExtension: String
        let mimeType: String
    }

    static let targetDimensions = [2_048, 1_536, 1_024]
    static let compressionQualities: [Double] = [0.82, 0.68, 0.52]

    func supportedFormat(for type: UTType) -> SupportedFormat? {
        if type.conforms(to: .jpeg) {
            return SupportedFormat(fileExtension: "jpg", mimeType: "image/jpeg")
        }
        if type.conforms(to: .png) {
            return SupportedFormat(fileExtension: "png", mimeType: "image/png")
        }
        if preservesGIF, type.conforms(to: .gif) {
            return SupportedFormat(fileExtension: "gif", mimeType: "image/gif")
        }
        if type.conforms(to: .webP) {
            return SupportedFormat(fileExtension: "webp", mimeType: "image/webp")
        }
        return nil
    }

    func convertToJPEG(source: CGImageSource, fileName: String) throws -> PreparedImageAttachment {
        for dimension in Self.targetDimensions {
            guard let image = thumbnail(from: source, maximumDimension: dimension) else { continue }

            for quality in Self.compressionQualities {
                guard let data = jpegData(from: image, quality: quality) else { continue }
                if data.count <= ImageAttachmentConstraints.maximumBytes {
                    return PreparedImageAttachment(
                        data: data,
                        fileName: normalizedFileName(fileName, extension: "jpg"),
                        mimeType: "image/jpeg"
                    )
                }
            }
        }
        throw PrepareImageAttachmentError.conversionFailed
    }

    func thumbnail(from source: CGImageSource, maximumDimension: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    func jpegData(from image: CGImage, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }

        let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    func normalizedFileName(_ fileName: String, extension fileExtension: String) -> String {
        let baseName = (fileName as NSString).deletingPathExtension
        return "\(baseName.isEmpty ? "image" : baseName).\(fileExtension)"
    }
}

private nonisolated enum PrepareImageAttachmentError: LocalizedError {
    case invalidImage
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            String(localized: "The selected file is not a valid image.")
        case .conversionFailed:
            String(localized: "The selected image could not be prepared. Please choose another image.")
        }
    }
}
