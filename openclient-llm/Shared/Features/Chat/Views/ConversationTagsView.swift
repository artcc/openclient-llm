//
//  ConversationTagsView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 01/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct ConversationTagsView: View {
    // MARK: - Properties

    let conversationTitle: String
    let existingTags: [ConversationTag]
    let availableTags: [ConversationTag]
    let onSave: ([ConversationTag]) -> Void

    @State private var tags: [ConversationTag]
    @State private var newTagText: String = ""
    @State private var newTagColor: TagColor = .orange
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFieldFocused: Bool

    // MARK: - Init

    init(
        conversationTitle: String,
        existingTags: [ConversationTag],
        availableTags: [ConversationTag],
        onSave: @escaping ([ConversationTag]) -> Void
    ) {
        self.conversationTitle = conversationTitle
        self.existingTags = existingTags
        self.availableTags = availableTags
        self.onSave = onSave
        _tags = State(initialValue: existingTags)
    }

    // MARK: - View

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField(String(localized: "Add tag..."), text: $newTagText)
                            .focused($isFieldFocused)
                            .autocorrectionDisabled()
#if os(iOS)
                            .textInputAutocapitalization(.never)
#endif
                            .onSubmit { addTag() }
                            .onChange(of: newTagText) { _, _ in
                                if let existingTag {
                                    newTagColor = existingTag.color
                                }
                            }

                        Button(String(localized: "Add")) {
                            addTag()
                        }
                        .disabled(newTagText.trimmingCharacters(in: .whitespaces).isEmpty || tags.count >= 3)
                    }
                    colorPicker
                } header: {
                    Text(String(localized: "New Tag"))
                } footer: {
                    if existingTag != nil {
                        Text(String(localized: "Existing tags keep their assigned color."))
                    }
                }

                if !tags.isEmpty {
                    Section {
                        ForEach(tags, id: \.self) { tag in
                            HStack {
                                Image(systemName: "tag.fill")
                                    .foregroundStyle(tag.color.displayColor)
                                    .accessibilityHidden(true)
                                Text(tag.name)
                                    .accessibilityValue(tag.color.localizedName)
                                Spacer()
#if os(macOS)
                                Button(role: .destructive) {
                                    tags.removeAll { $0 == tag }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help(String(localized: "Delete"))
                                .accessibilityLabel(String(localized: "Delete"))
#endif
                            }
                        }
                        .onDelete { indexSet in
                            tags.remove(atOffsets: indexSet)
                        }
                    } header: {
                        Text(String(localized: "Tags"))
                    } footer: {
#if os(iOS)
                        Text(tags.count >= 3
                            ? String(localized: "Maximum of 3 tags reached. Remove one to add another.")
                            : String(localized: "Swipe left to remove a tag."))
#else
                        if tags.count >= 3 {
                            Text(String(localized: "Maximum of 3 tags reached. Remove one to add another."))
                        }
#endif
                    }
                }
            }
#if os(macOS)
            .formStyle(.grouped)
#endif
            .navigationTitle(conversationTitle.isEmpty ? String(localized: "Tags") : conversationTitle)
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        onSave(tags)
                        dismiss()
                    }
                }
            }
        }
#if os(macOS)
        .frame(width: 500, height: 460)
#endif
    }
}

// MARK: - Private

private extension ConversationTagsView {
    var existingTag: ConversationTag? {
        let name = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        return availableTags.first { $0.name == name }
    }

    @ViewBuilder
    var colorPicker: some View {
        Picker(String(localized: "Color"), selection: $newTagColor) {
            ForEach(TagColor.allCases) { color in
                Label {
                    Text(color.localizedName)
                } icon: {
                    Image(systemName: "tag.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(color.displayColor)
                }
                .tag(color)
            }
        }
#if os(iOS)
        .pickerStyle(.navigationLink)
#else
        .pickerStyle(.radioGroup)
#endif
        .disabled(existingTag != nil)
    }

    func addTag() {
        let name = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !tags.contains(where: { $0.name == name }), tags.count < 3 else { return }
        tags.append(existingTag ?? ConversationTag(name: name, color: newTagColor))
        newTagText = ""
        newTagColor = .orange
    }
}

#Preview {
    ConversationTagsView(
        conversationTitle: "My conversation",
        existingTags: [
            ConversationTag(name: "swift", color: .orange),
            ConversationTag(name: "ai", color: .blue)
        ],
        availableTags: [
            ConversationTag(name: "swift", color: .orange),
            ConversationTag(name: "ai", color: .blue)
        ]
    ) { _ in }
}
