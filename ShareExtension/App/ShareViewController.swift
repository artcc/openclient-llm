//
//  ShareViewController.swift
//  ShareExtension
//
//  Created by Arturo Carretero Calvo on 18/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Social
import SwiftUI
import UniformTypeIdentifiers

final class ShareViewController: SLComposeServiceViewController {
    // MARK: - SLComposeServiceViewController

    override func isContentValid() -> Bool {
        true
    }

    override func didSelectPost() {
        let composedText = contentText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText = composedText?.isEmpty == false ? composedText : nil
        let inputItems = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let context = extensionContext
        Task { @MainActor in
            let item = await buildShareItem(composedText: trimmedText, from: inputItems)
            try? ShareExtensionStore.save(item)
            context?.completeRequest(returningItems: []) { _ in
                guard let appURL = URL(string: "openclient://share") else { return }
                Task { @MainActor in
                    self.openContainingApp(url: appURL)
                }
            }
        }
    }

    override func configurationItems() -> [Any]! {
        []
    }
}

// MARK: - Private

private extension ShareViewController {
    /// Opens the containing app by traversing the responder chain to reach UIApplication.
    /// This is the reliable approach for Share Extensions — NSExtensionContext.open()
    /// is only available for Action/Today extensions, not Share extensions.
    func openContainingApp(url: URL) {
        var responder: UIResponder? = self
        while let current = responder {
            if let app = current as? UIApplication {
                app.open(url, options: [:], completionHandler: nil)
                return
            }
            responder = current.next
        }
    }

    func buildShareItem(composedText: String?, from items: [NSExtensionItem]) async -> ShareExtensionItem {
        var attachments: [ShareExtensionItem.Attachment] = []
        var detectedURL: String?
        var detectedText: String?

        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let attachment = await processImage(provider) {
                        attachments.append(attachment)
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                    if let attachment = await processPDF(provider) {
                        attachments.append(attachment)
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if detectedURL == nil {
                        detectedURL = await loadURL(provider)
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if detectedText == nil {
                        detectedText = await loadPlainText(provider)
                    }
                }
            }
        }

        return ShareExtensionItem(
            text: composedText ?? detectedText,
            url: detectedURL,
            attachments: attachments,
            createdAt: Date()
        )
    }

    func processImage(_ provider: NSItemProvider) async -> ShareExtensionItem.Attachment? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data,
                      let relativePath = try? ShareExtensionStore.writeAttachmentData(data, fileName: "photo.jpg")
                else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: ShareExtensionItem.Attachment(
                    fileName: "photo.jpg",
                    mimeType: "image/jpeg",
                    relativePath: relativePath
                ))
            }
        }
    }

    func processPDF(_ provider: NSItemProvider) async -> ShareExtensionItem.Attachment? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.pdf.identifier) { data, _ in
                guard let data,
                      let relativePath = try? ShareExtensionStore.writeAttachmentData(data, fileName: "document.pdf")
                else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: ShareExtensionItem.Attachment(
                    fileName: "document.pdf",
                    mimeType: "application/pdf",
                    relativePath: relativePath
                ))
            }
        }
    }

    func loadURL(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                continuation.resume(returning: (item as? URL)?.absoluteString)
            }
        }
    }

    func loadPlainText(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                continuation.resume(returning: item as? String)
            }
        }
    }
}
