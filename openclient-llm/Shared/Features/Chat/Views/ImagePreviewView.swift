//
//  ImagePreviewView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 01/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI
#if canImport(UIKit)
import SwiftUI
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Helper

struct ExpandedImage: Identifiable {
    let id = UUID()
    let data: Data
}

// MARK: - View

struct ImagePreviewView: View {
    // MARK: - Properties

    let data: Data

    @Environment(\.dismiss) private var dismiss
    @GestureState private var gestureScale: CGFloat = 1.0
    @State private var steadyScale: CGFloat = 1.0
#if os(macOS)
    @State private var imageToExport: Data?
#endif

    private var zoomScale: CGFloat { max(1.0, min(steadyScale * gestureScale, 6.0)) }

    // MARK: - View

    var body: some View {
        NavigationStack {
            Group {
#if os(iOS)
                if let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(zoomScale)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea(edges: .bottom)
                        .gesture(
                            MagnificationGesture()
                                .updating($gestureScale) { value, state, _ in state = value }
                                .onEnded { value in
                                    steadyScale = max(1.0, min(steadyScale * value, 6.0))
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                steadyScale = 1.0
                            }
                        }
                        .accessibilityLabel(String(localized: "Image preview"))
                        .accessibilityValue(Text("Zoom \(Int(zoomScale * 100)) percent"))
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment:
                                steadyScale = min(steadyScale + 1, 6)
                            case .decrement:
                                steadyScale = max(steadyScale - 1, 1)
                            @unknown default:
                                break
                            }
                        }
                        .accessibilityAction(named: Text("Reset Zoom")) {
                            steadyScale = 1.0
                        }
                }
#elseif os(macOS)
                if let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel(String(localized: "Image preview"))
                }
#endif
            }
            .navigationTitle(String(localized: "Generated Image"))
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

                ToolbarItem(placement: .primaryAction) {
                    saveButton
                }
            }
        }
#if os(macOS)
        .imageExporter(data: $imageToExport) {
            dismiss()
        }
#endif
    }
}

// MARK: - Private

private extension ImagePreviewView {
    var saveButton: some View {
#if os(iOS)
        Button {
            saveImageToPhotos(data)
        } label: {
            Label(String(localized: "Save to Photos"), systemImage: "square.and.arrow.down")
        }
#elseif os(macOS)
        Button {
            imageToExport = data
        } label: {
            Label(String(localized: "Save Image..."), systemImage: "square.and.arrow.down")
        }
#endif
    }

#if os(iOS)
    func saveImageToPhotos(_ imageData: Data) {
        guard let image = UIImage(data: imageData) else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }
#endif
}

#Preview {
    ImagePreviewView(data: Data())
}
