//
//  WebContentView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI
@preconcurrency import WebKit

struct WebContentView: View {
    // MARK: - Properties

    let title: String
    let url: URL

    @Environment(\.dismiss) private var dismiss

    // MARK: - View

    var body: some View {
#if os(macOS)
        macOSBody
#else
        iOSBody
#endif
    }
}

// MARK: - Private

private extension WebContentView {
#if os(macOS)
    var macOSBody: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
                HStack {
                    Spacer()
                    Button(String(localized: "Close")) {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
            .padding()
            Divider()
            MacWebView(url: url)
        }
        .frame(width: 700, height: 500)
    }
#endif

    var iOSBody: some View {
        NavigationStack {
            WebView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title)
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
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Close"))
                    }
                }
        }
    }
}

// MARK: - WebView (iOS)

#if os(iOS)
private struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - MacWebView (macOS)

#else
private struct MacWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            // Silent — the WKWebView shows its own error page
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            // Silent — the WKWebView shows its own error page
        }
    }
}
#endif

#Preview {
    if let url = URL(string: "https://www.arturocarreterocalvo.com/openclient-llm/privacy") {
        WebContentView(title: "Privacy Policy", url: url)
    }
}
