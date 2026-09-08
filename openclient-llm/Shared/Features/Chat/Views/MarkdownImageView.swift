//
//  MarkdownImageView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 29/07/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct MarkdownImageView: View {
    // MARK: - Properties

    let alt: String
    let urlString: String
    var onLayoutChanged: (() -> Void)?

    @State private var loadState: LoadState = .loading

    // MARK: - View

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                switch loadState {
                case .loading:
                    ProgressView()
                        .accessibilityLabel(String(localized: "Loading image..."))
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                case .loaded(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                case .failed:
                    HStack(spacing: 6) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .foregroundStyle(.secondary)
                        Text("Image could not be loaded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            if !alt.isEmpty {
                Text(alt)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .task {
            await loadImage()
        }
    }
}

// MARK: - Load State

private extension MarkdownImageView {
    enum LoadState: Equatable {
        case loading
        case loaded(Image)
        case failed

        static func == (lhs: LoadState, rhs: LoadState) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading), (.failed, .failed):
                return true
            case (.loaded, .loaded):
                return true
            default:
                return false
            }
        }
    }

    func loadImage() async {
        guard let url = URL(string: urlString) else {
            finishLoading(with: .failed)
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            #if os(macOS)
            if let nsImage = NSImage(data: data) {
                finishLoading(with: .loaded(Image(nsImage: nsImage)))
            } else {
                finishLoading(with: .failed)
            }
            #else
            if let uiImage = UIImage(data: data) {
                finishLoading(with: .loaded(Image(uiImage: uiImage)))
            } else {
                finishLoading(with: .failed)
            }
            #endif
        } catch {
            finishLoading(with: .failed)
        }
    }

    func finishLoading(with state: LoadState) {
        loadState = state
        onLayoutChanged?()
    }
}

#Preview {
    VStack(spacing: 16) {
        MarkdownImageView(
            alt: "Swift logo",
            urlString: "https://developer.apple.com/swift/images/swift-og.png"
        )
        MarkdownImageView(alt: "", urlString: "https://invalid.url/notfound.png")
    }
    .padding()
    .frame(width: 320)
}
