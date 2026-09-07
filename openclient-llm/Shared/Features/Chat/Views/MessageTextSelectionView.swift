//
//  MessageTextSelectionView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 02/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

#if os(iOS)
import SwiftUI
import UIKit

struct MessageTextSelectionView: View {
    // MARK: - Properties

    let text: String

    @Environment(\.dismiss) private var dismiss

    // MARK: - View

    var body: some View {
        NavigationStack {
            SelectableMessageTextView(text: text)
                .navigationTitle(String(localized: "Select Text"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Done")) {
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - SelectableMessageTextView

private struct SelectableMessageTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textColor = .label
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        textView.textContainer.lineFragmentPadding = 0
        textView.text = text
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        guard textView.text != text else { return }
        textView.text = text
    }
}

#Preview {
    MessageTextSelectionView(
        text: "Select any part of this response and copy only the text you need."
    )
}
#endif
