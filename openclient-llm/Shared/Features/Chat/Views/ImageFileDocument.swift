//
//  ImageFileDocument.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 09/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import ImageIO
import SwiftUI
import UniformTypeIdentifiers

nonisolated struct ImageFileDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        let identifiers = CGImageSourceCopyTypeIdentifiers() as? [String] ?? []
        return identifiers.compactMap { UTType($0) }
    }

    let data: Data
    let contentType: UTType

    init(data: Data) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let identifier = CGImageSourceGetType(source),
              let contentType = UTType(identifier as String),
              contentType.conforms(to: .image),
              contentType.preferredFilenameExtension != nil else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
        self.contentType = contentType
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try self.init(data: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
