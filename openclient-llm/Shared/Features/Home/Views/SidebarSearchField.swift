//
//  SidebarSearchField.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 15/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

#if os(iOS)
struct SidebarSearchField: View {
    // MARK: - Properties

    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var focusRequested: Bool
    let onActivated: () -> Void

    // Keep focus in the sidebar's view hierarchy, rather than the TabView's parent.
    @FocusState private var isFieldFocused: Bool

    // MARK: - View

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(String(localized: "Search") + "...", text: $text)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isFieldFocused)
                .accessibilityIdentifier("iPadSidebarSearch")
                .onSubmit { isFieldFocused = false }
            if !text.isEmpty {
                Button {
                    text = ""
                    onActivated()
                    isFieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Clear Search"))
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, text.isEmpty ? 12 : 0)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(.quaternary, in: .capsule)
        .onChange(of: isFieldFocused) { _, focused in
            isFocused = focused
            if focused { onActivated() }
        }
        .onChange(of: isFocused, initial: true) { _, focused in
            isFieldFocused = focused
        }
        .task(id: focusRequested) {
            guard focusRequested else { return }
            // Reapply focus after the detail change, outside the tap's navigation update.
            await Task.yield()
            guard !Task.isCancelled, focusRequested else { return }
            isFieldFocused = true
            isFocused = true
            focusRequested = false
        }
    }
}

#Preview {
    @Previewable @State var text = ""
    @Previewable @State var isFocused = false
    @Previewable @State var focusRequested = false

    SidebarSearchField(
        text: $text,
        isFocused: $isFocused,
        focusRequested: $focusRequested,
        onActivated: {}
    )
    .padding()
}
#endif
