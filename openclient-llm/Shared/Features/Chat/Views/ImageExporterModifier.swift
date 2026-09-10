//
//  ImageExporterModifier.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 09/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

struct ImageExporterModifier: ViewModifier {
    @Binding var data: Data?
    let onSuccess: () -> Void

    @State private var document: ImageFileDocument?
    @State private var isPresented = false
    @State private var showError = false
    @State private var defaultFilename = "image"

    func body(content: Content) -> some View {
        content
            .fileExporter(
                isPresented: $isPresented,
                document: document,
                contentType: document?.contentType ?? .image,
                defaultFilename: defaultFilename
            ) { result in
                switch result {
                case .success:
                    LogManager.success("Image exported")
                    onSuccess()
                case .failure(let error):
                    let cocoaError = error as NSError
                    guard cocoaError.domain != NSCocoaErrorDomain || cocoaError.code != NSUserCancelledError else {
                        return
                    }
                    LogManager.error("Image export failed (code: \(cocoaError.code))")
                    showError = true
                }
            }
            .onChange(of: data) { _, imageData in
                guard let imageData else { return }
                showError = false
                do {
                    document = try ImageFileDocument(data: imageData)
                    defaultFilename = "image-\(Int(Date().timeIntervalSince1970))"
                    isPresented = true
                } catch {
                    LogManager.error("Image export preparation failed")
                    showError = true
                    data = nil
                }
            }
            .onChange(of: isPresented) { _, presented in
                guard !presented else { return }
                data = nil
                document = nil
            }
            .safeAreaInset(edge: .bottom) {
                if showError {
                    errorBanner
                }
            }
    }

    private var errorBanner: some View {
        HStack {
            Label("Unable to save the image. Please try again.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Button {
                showError = false
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel(Text("Dismiss error"))
        }
        .font(.caption)
        .padding(8)
        .background(.regularMaterial, in: .rect(cornerRadius: 8))
    }
}

extension View {
    func imageExporter(data: Binding<Data?>, onSuccess: @escaping () -> Void = {}) -> some View {
        modifier(ImageExporterModifier(data: data, onSuccess: onSuccess))
    }
}
#endif
