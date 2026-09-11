//
//  AttachmentImageView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 16/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI
#if canImport(UIKit)
import SwiftUI
#elseif canImport(AppKit)
import AppKit
#endif

/// Async image thumbnail for a `ChatMessage.Attachment` stored on disk.
///
/// Loads `Data` from disk only when needed (on `.task` appearance). Shows a
/// loading placeholder, then the image or a fallback document card on failure.
struct AttachmentImageView: View {
    // MARK: - Properties

    let attachment: ChatMessage.Attachment
    var thumbnailSize: CGFloat = 175

    private let repository: AttachmentRepositoryProtocol

    @State private var loadedData: Data?
    @State private var isLoaded: Bool = false
    @State private var showPreview: Bool = false
#if os(macOS)
    @State private var imageToExport: Data?
#endif

    // MARK: - Init

    init(
        attachment: ChatMessage.Attachment,
        thumbnailSize: CGFloat = 175,
        repository: AttachmentRepositoryProtocol = AttachmentRepository()
    ) {
        self.attachment = attachment
        self.thumbnailSize = thumbnailSize
        self.repository = repository
    }

    // MARK: - View

    var body: some View {
        Group {
            if let data = loadedData {
                thumbnail(data: data)
            } else if isLoaded {
                fallbackCard
            } else {
                loadingPlaceholder
            }
        }
        .task(id: attachment.id) {
            guard loadedData == nil else { return }
            loadedData = attachment.transientData ?? (try? repository.load(attachment: attachment))
            isLoaded = true
        }
        .sheet(isPresented: $showPreview) {
            if let data = loadedData {
                ImagePreviewView(data: data)
            }
        }
#if os(macOS)
        .imageExporter(data: $imageToExport)
#endif
    }
}

// MARK: - Private

private extension AttachmentImageView {
    @ViewBuilder
    func thumbnail(data: Data) -> some View {
        #if os(iOS)
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: thumbnailSize, height: thumbnailSize)
                .clipShape(.rect(cornerRadius: 12))
                .contentShape(.rect(cornerRadius: 12))
                .onTapGesture { showPreview = true }
                .contextMenu { imageContextMenu(data: data) }
                .accessibilityLabel(Text("Image attachment \(attachment.fileName)"))
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(String(localized: "Opens the image preview"))
        } else {
            fallbackCard
        }
        #elseif os(macOS)
        if let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: thumbnailSize, height: thumbnailSize)
                .clipShape(.rect(cornerRadius: 12))
                .contentShape(.rect(cornerRadius: 12))
                .onTapGesture { showPreview = true }
                .contextMenu { imageContextMenu(data: data) }
                .accessibilityLabel(Text("Image attachment \(attachment.fileName)"))
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(String(localized: "Opens the image preview"))
        } else {
            fallbackCard
        }
        #endif
    }

    var loadingPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary)
                .frame(width: thumbnailSize, height: thumbnailSize)
            ProgressView()
                .accessibilityLabel(Text("Loading image \(attachment.fileName)"))
                .tint(.secondary)
        }
    }

    var fallbackCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Text(String(localized: "Image"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    @ViewBuilder
    func imageContextMenu(data: Data) -> some View {
        #if os(iOS)
        Button {
            saveImageToPhotos(data)
        } label: {
            Label(String(localized: "Save to Photos"), systemImage: "photo.badge.plus")
        }
        #elseif os(macOS)
        Button {
            imageToExport = data
        } label: {
            Label(String(localized: "Save Image..."), systemImage: "arrow.down.circle")
        }
        #endif
        Button {
            copyImageToClipboard(data)
        } label: {
            Label(String(localized: "Copy Image"), systemImage: "doc.on.doc")
        }
    }

    #if os(iOS)
    func saveImageToPhotos(_ data: Data) {
        guard let image = UIImage(data: data) else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }
    #endif

    func copyImageToClipboard(_ data: Data) {
        #if os(iOS)
        guard let image = UIImage(data: data) else { return }
        UIPasteboard.general.image = image
        #elseif os(macOS)
        guard let image = NSImage(data: data) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        #endif
    }
}

#Preview {
    AttachmentImageView(
        attachment: ChatMessage.Attachment(
            type: .image,
            fileName: "preview.jpg",
            mimeType: "image/jpeg",
            fileRelativePath: ""
        )
    )
}
