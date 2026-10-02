//
//  ChatView+DragDrop.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 18/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - ChatDropModifier

/// Applies drag-and-drop support to the chat content area.
///
/// Accepted content types:
/// - Plain text → pre-fills the message input field
/// - Images (JPEG / PNG / HEIC / generic) → added as a pending image attachment
/// - PDF → added as a pending PDF attachment
/// - File URLs → inspected by extension; images and PDFs are handled, other types are ignored
///
/// This modifier is invisible: it adds no permanent UI and does not change the existing layout.
/// The system provides a standard drop-target highlight while the user drags content over the view.
struct ChatDropModifier: ViewModifier {
    // MARK: - Properties

    let onItems: ([ChatViewModel.AttachmentInput]) -> Void

    // MARK: - Body

    func body(content: Content) -> some View {
        content
            .onDrop(of: [.plainText, .image, .pdf, .fileURL], isTargeted: nil) { providers in
                onItems(Self.inputs(from: providers))
                return !providers.isEmpty
            }
    }

    static func inputs(from providers: [NSItemProvider]) -> [ChatViewModel.AttachmentInput] {
        providers.map { provider in
            ChatViewModel.AttachmentInput { await load(provider) }
        }
    }
}

// MARK: - Private

private extension ChatDropModifier {
    // MARK: Dispatch

    static func load(_ provider: NSItemProvider) async -> ChatViewModel.AttachmentInputValue? {
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            return await loadText(from: provider).map { .text($0) }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return await loadImageData(from: provider).map { .file($0.0, $0.1, .image) }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            return await loadPDFData(from: provider).map { .file($0.0, $0.1, .pdf) }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return await loadFile(from: provider)
        }
        return nil
    }

    // MARK: Loaders

    static func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                switch item {
                case let string as String:
                    continuation.resume(returning: string)
                case let data as Data:
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                default:
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    static func loadImageData(from provider: NSItemProvider) async -> (Data, String)? {
        let candidates: [(String, String)] = [
            (UTType.jpeg.identifier, "jpg"),
            (UTType.png.identifier, "png"),
            ("public.heic", "heic"),
            (UTType.image.identifier, "jpg")
        ]
        for (typeId, ext) in candidates where provider.hasItemConformingToTypeIdentifier(typeId) {
            if let data = await loadData(from: provider, typeIdentifier: typeId) {
                let base = provider.suggestedName ?? "image"
                let name = base.contains(".") ? base : "\(base).\(ext)"
                return (data, name)
            }
        }
        return nil
    }

    static func loadPDFData(from provider: NSItemProvider) async -> (Data, String)? {
        guard let data = await loadData(from: provider, typeIdentifier: UTType.pdf.identifier) else {
            return nil
        }
        let base = provider.suggestedName ?? "document"
        let name = base.contains(".") ? base : "\(base).pdf"
        return (data, name)
    }

    static func loadFile(from provider: NSItemProvider) async -> ChatViewModel.AttachmentInputValue? {
        guard let url = await loadFileURL(from: provider) else { return nil }
        guard !Task.isCancelled else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "heic", "heif", "gif", "webp":
            return .file(data, url.lastPathComponent, .image)
        case "pdf":
            return .file(data, url.lastPathComponent, .pdf)
        default:
            return nil
        }
    }

    // MARK: NSItemProvider helpers

    static func loadData(from provider: NSItemProvider, typeIdentifier: String) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                continuation.resume(returning: item as? URL)
            }
        }
    }
}
