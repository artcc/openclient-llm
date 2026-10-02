//
//  AttachmentPickerView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 31/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ImagePickerModifier: ViewModifier {
    // MARK: - Properties

    @Binding var isPresented: Bool
    let onImagesSelected: ([ChatViewModel.ImageInput]) -> Void

    @State private var selectedItems: [PhotosPickerItem] = []

    // MARK: - View

    func body(content: Content) -> some View {
        content
            .photosPicker(
                isPresented: $isPresented,
                selection: $selectedItems,
                selectionBehavior: .ordered,
                matching: .images
            )
            .onChange(of: selectedItems) { _, items in
                guard !items.isEmpty else { return }
                onImagesSelected(items.enumerated().map { index, item in
                    ChatViewModel.ImageInput(fileName: String(localized: "Photo \(index + 1)")) {
                        guard let data = try await item.loadTransferable(type: Data.self) else {
                            throw ImageGenerationInputError.unreadableImage
                        }
                        return data
                    }
                })
                selectedItems = []
            }
    }
}

struct DocumentPickerModifier: ViewModifier {
    // MARK: - Properties

    @Binding var isPresented: Bool
    let onAttachmentData: (Data, String, ChatMessage.AttachmentType) -> Void

    // MARK: - View

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $isPresented,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let gotAccess = url.startAccessingSecurityScopedResource()
                    defer {
                        if gotAccess { url.stopAccessingSecurityScopedResource() }
                    }
                    if let data = try? Data(contentsOf: url) {
                        onAttachmentData(data, url.lastPathComponent, .pdf)
                    }
                case .failure:
                    break
                }
            }
    }
}

#if os(macOS)
struct ImageFilePickerModifier: ViewModifier {
    // MARK: - Properties

    @Binding var isPresented: Bool
    let onAttachmentData: (Data, String, ChatMessage.AttachmentType) -> Void

    // MARK: - View

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $isPresented,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let gotAccess = url.startAccessingSecurityScopedResource()
                    defer {
                        if gotAccess { url.stopAccessingSecurityScopedResource() }
                    }
                    if let data = try? Data(contentsOf: url) {
                        onAttachmentData(data, url.lastPathComponent, .image)
                    }
                case .failure:
                    break
                }
            }
    }
}
#endif

extension View {
    func imagePicker(
        isPresented: Binding<Bool>,
        onImagesSelected: @escaping ([ChatViewModel.ImageInput]) -> Void
    ) -> some View {
        modifier(ImagePickerModifier(isPresented: isPresented, onImagesSelected: onImagesSelected))
    }

    func documentPicker(
        isPresented: Binding<Bool>,
        onAttachmentData: @escaping (Data, String, ChatMessage.AttachmentType) -> Void
    ) -> some View {
        modifier(DocumentPickerModifier(isPresented: isPresented, onAttachmentData: onAttachmentData))
    }

#if os(macOS)
    func imageFilePicker(
        isPresented: Binding<Bool>,
        onAttachmentData: @escaping (Data, String, ChatMessage.AttachmentType) -> Void
    ) -> some View {
        modifier(ImageFilePickerModifier(isPresented: isPresented, onAttachmentData: onAttachmentData))
    }
#endif
}
