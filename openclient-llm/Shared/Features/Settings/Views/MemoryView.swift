//
//  MemoryView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 16/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct MemoryView: View {
    // MARK: - Properties

    @State private var viewModel = MemoryViewModel()
    @State private var isShowingAddSheet = false
    @State private var editingItem: MemoryItem?
    @Environment(\.dismiss) private var dismiss

    // MARK: - View

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .loading:
                    ProgressView()
                        .tint(.secondary)
                case .loaded(let loadedState):
                    loadedView(loadedState)
                }
            }
            .navigationTitle(String(localized: "Memory"))
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isShowingAddSheet) {
                MemoryItemEditorView { content in
                    viewModel.send(.addItem(content: content))
                }
            }
            .sheet(item: $editingItem) { item in
                MemoryItemEditorView(initialContent: item.content) { content in
                    viewModel.send(.editItem(id: item.id, content: content))
                }
            }
        }
        .task {
            viewModel.send(.viewAppeared)
        }
    }
}

// MARK: - Private

private extension MemoryView {
    func loadedView(_ loadedState: MemoryViewModel.LoadedState) -> some View {
        VStack(spacing: 0) {
            if let errorMessage = loadedState.errorMessage {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    Button(String(localized: "Retry")) {
                        viewModel.send(.retrySynchronization)
                    }
                    .disabled(loadedState.isSynchronizing)
                }
                .padding()
            }

            if loadedState.items.isEmpty {
                emptyState
            } else {
                itemsList(loadedState.items)
            }
        }
    }

    var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(String(localized: "No Memory Items"))
                .font(.title3)
                .fontWeight(.semibold)
            Text(String(localized: "Add things you want the assistant to remember across all conversations."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func itemsList(_ items: [MemoryItem]) -> some View {
#if os(macOS)
        List {
            ForEach(items) { item in
                macOSItemRow(item)
            }
        }
#else
        List {
            ForEach(items) { item in
                iOSItemRow(item)
            }
            .onDelete { indexSet in
                for index in indexSet {
                    viewModel.send(.deleteItem(id: items[index].id))
                }
            }
        }
#endif
    }

#if os(iOS)
    func iOSItemRow(_ item: MemoryItem) -> some View {
        VStack(alignment: .leading, spacing: 7.5) {
            itemText(item)

            HStack(spacing: 6) {
                itemMetadata(item)

                Spacer()

                itemToggle(item)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                editingItem = item
            } label: {
                Label(String(localized: "Edit"), systemImage: "pencil")
            }
            Button(role: .destructive) {
                viewModel.send(.deleteItem(id: item.id))
            } label: {
                Label(String(localized: "Delete"), systemImage: "trash")
            }
        }
    }
#endif

#if os(macOS)
    func macOSItemRow(_ item: MemoryItem) -> some View {
        VStack(alignment: .leading, spacing: 7.5) {
            itemText(item)

            HStack(spacing: 6) {
                itemMetadata(item)

                Spacer()

                Button {
                    editingItem = item
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)

                Button(role: .destructive) {
                    viewModel.send(.deleteItem(id: item.id))
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)

                itemToggle(item)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }
#endif

    func itemText(_ item: MemoryItem) -> some View {
        Text(item.content)
            .font(.body)
            .foregroundStyle(item.isEnabled ? .primary : .secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    func itemMetadata(_ item: MemoryItem) -> some View {
        HStack(spacing: 6) {
            sourceLabel(item.source)
            Text(item.createdAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    func itemToggle(_ item: MemoryItem) -> some View {
        Toggle(String(localized: "Use this memory"), isOn: Binding(
            get: { item.isEnabled },
            set: { _ in viewModel.send(.toggleItem(id: item.id)) }
        ))
        .labelsHidden()
    }

    func sourceLabel(_ source: MemoryItem.Source) -> some View {
        let label: String
        let icon: String
        let color: Color
        switch source {
        case .user:
            label = String(localized: "You")
            icon = "person.fill"
            color = .blue
        case .model:
            label = String(localized: "Model")
            icon = "brain.head.profile"
            color = .purple
        }

        return HStack(spacing: 3) {
            Image(systemName: icon)
            Text(label)
        }
        .font(.caption2)
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - MemoryItemEditorView

private struct MemoryItemEditorView: View {
    // MARK: - Properties

    var initialContent: String = ""
    var onSave: (String) -> Void

    @State private var content: String = ""
    @Environment(\.dismiss) private var dismiss

    // MARK: - View

    var body: some View {
        NavigationStack {
            Group {
#if os(macOS)
                macOSEditorView
#else
                Form {
                    Section {
                        TextField(
                            String(localized: "e.g. User prefers concise answers"),
                            text: $content,
                            axis: .vertical
                        )
                        .lineLimit(4...)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.sentences)
                    } header: {
                        Text(String(localized: "Memory Content"))
                    } footer: {
                        Text(String(localized: "This will be injected into every conversation's system prompt."))
                    }
                }
#endif
            }
            .navigationTitle(
                initialContent.isEmpty
                ? String(localized: "New Memory")
                : String(localized: "Edit Memory")
            )
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
                        onSave(content)
                        dismiss()
                    }
                    .disabled(content.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .task {
            content = initialContent
        }
    }

#if os(macOS)
    var macOSEditorView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                macOSContentField
            }
            .padding(16)
        }
    }

    var macOSContentField: some View {
        macOSField(
            header: String(localized: "Memory Content"),
            footer: String(localized: "This will be injected into every conversation's system prompt.")
        ) {
            TextField(
                String(localized: "e.g. User prefers concise answers"),
                text: $content,
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(4...)
            .autocorrectionDisabled()
        }
    }

    func macOSField<Content: View>(
        header: String,
        footer: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(header)
                .font(.headline)
                .foregroundStyle(.primary)
            content()
            Text(footer)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
#endif
}

#Preview {
    MemoryView()
}
