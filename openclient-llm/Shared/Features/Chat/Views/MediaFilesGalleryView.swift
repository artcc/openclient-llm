//
//  MediaFilesGalleryView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 10/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import PDFKit
import SwiftUI

// MARK: - Media Item

private struct MediaItem: Identifiable {
    let id: UUID
    let attachment: ChatMessage.Attachment
    let messageId: UUID
    let timestamp: Date
}

// MARK: - View

struct MediaFilesGalleryView: View {
    // MARK: - Properties

    let messages: [ChatMessage]
    var onGoToMessage: ((UUID) -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var previewDocument: MediaItem?

    private var imageItems: [MediaItem] {
        messages.flatMap { message in
            message.attachments
                .filter { $0.type == .image }
                .map { MediaItem(id: $0.id, attachment: $0, messageId: message.id, timestamp: message.timestamp) }
        }
    }

    private var documentItems: [MediaItem] {
        messages.flatMap { message in
            message.attachments
                .filter { $0.type == .pdf }
                .map { MediaItem(id: $0.id, attachment: $0, messageId: message.id, timestamp: message.timestamp) }
        }
    }

    // MARK: - View

    var body: some View {
        NavigationStack {
            Group {
                if imageItems.isEmpty && documentItems.isEmpty {
                    emptyState
                } else {
                    gallery
                }
            }
            .navigationTitle(String(localized: "Media & Files"))
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) {
                        dismiss()
                    }
                }
            }
        }
        .sheet(item: $previewDocument) { item in
            PDFPreviewView(attachment: item.attachment)
        }
    }
}

// MARK: - Private

private extension MediaFilesGalleryView {
    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(String(localized: "No Media or Files"))
                .font(.headline)
                .foregroundStyle(.primary)
            Text(String(localized: "Images and documents you attach to messages will appear here."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var gallery: some View {
        List {
            if !imageItems.isEmpty {
                Section(String(localized: "Images")) {
                    imagesGrid
                }
            }
            if !documentItems.isEmpty {
                Section(String(localized: "Documents")) {
                    ForEach(documentItems) { item in
                        documentRow(item)
                    }
                }
            }
        }
    }

    var imagesGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 90, maximum: 120))]
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(imageItems) { item in
                imageThumbnail(item)
            }
        }
        .padding(.vertical, 4)
    }

    func imageThumbnail(_ item: MediaItem) -> some View {
        ZStack(alignment: .bottomTrailing) {
            AttachmentImageView(attachment: item.attachment, thumbnailSize: 90)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            goToMessageButton(messageId: item.messageId)
                .padding(4)
        }
    }

    func documentRow(_ item: MediaItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.attachment.fileName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(item.timestamp, style: .date)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(String(localized: "Opens the document preview"))
            .accessibilityAction {
                previewDocument = item
            }
            Spacer()
            goToMessageButton(messageId: item.messageId)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            previewDocument = item
        }
    }

    func goToMessageButton(messageId: UUID) -> some View {
        Button {
            dismiss()
            onGoToMessage?(messageId)
        } label: {
            Image(systemName: "arrow.forward.circle.fill")
                .font(.caption)
                .foregroundStyle(.white)
                .padding(4)
                .background(Color.appAccent.opacity(0.8), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Go to message"))
    }
}

// MARK: - PDF Preview

struct PDFPreviewView: View {
    // MARK: - Properties

    let attachment: ChatMessage.Attachment

    @Environment(\.dismiss) private var dismiss
    @State private var pdfData: Data?

    private let repository: AttachmentRepositoryProtocol

    // MARK: - Init

    init(
        attachment: ChatMessage.Attachment,
        repository: AttachmentRepositoryProtocol = AttachmentRepository()
    ) {
        self.attachment = attachment
        self.repository = repository
    }

    // MARK: - View

    var body: some View {
        NavigationStack {
            Group {
                if let data = pdfData {
                    PDFKitRepresentable(data: data)
                } else {
                    ProgressView()
                        .accessibilityLabel(String(localized: "Loading document"))
                        .tint(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(attachment.fileName)
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "Close"))
                }
            }
        }
        .task(id: attachment.id) {
            pdfData = try? repository.load(attachment: attachment)
        }
    }
}

// MARK: - PDFKit Representable

#if os(iOS)
private struct PDFKitRepresentable: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.document = PDFDocument(data: data)
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}
#elseif os(macOS)
private struct PDFKitRepresentable: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.document = PDFDocument(data: data)
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {}
}
#endif

// MARK: - Preview

#Preview {
    MediaFilesGalleryView(messages: [])
}
