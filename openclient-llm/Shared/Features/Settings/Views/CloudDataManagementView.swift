//
//  CloudDataManagementView.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 11/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct CloudDataManagementView: View {
    // MARK: - Properties

    @State private var viewModel: CloudDataManagementViewModel
    @State private var showsAllConversations = false
    @State private var showsAllMemoryItems = false

    // MARK: - Init

    init(viewModel: CloudDataManagementViewModel = CloudDataManagementViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    // MARK: - View

    var body: some View {
        content
            .navigationTitle(String(localized: "Manage iCloud Data"))
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .alert(
                confirmationTitle,
                isPresented: confirmationBinding
            ) {
                Button(String(localized: "Cancel"), role: .cancel) {
                    viewModel.send(.deletionCancelled)
                }
                Button(String(localized: "Delete"), role: .destructive) {
                    viewModel.send(.deletionConfirmed)
                }
            } message: {
                Text(confirmationMessage)
            }
            .task {
                viewModel.send(.viewAppeared)
            }
    }
}

// MARK: - Private

private extension CloudDataManagementView {
    @ViewBuilder
    var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView(String(localized: "Loading iCloud data..."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let loadedState):
            inventoryList(loadedState)
        case .empty:
            unavailableView(
                title: String(localized: "No Synchronized Data"),
                systemImage: "icloud",
                description: String(localized: "There is no synchronized app data in iCloud."),
                showsRetry: true
            )
        case .pending:
            unavailableView(
                title: String(localized: "iCloud Data Is Downloading"),
                systemImage: "icloud.and.arrow.down",
                description: String(
                    localized: "Some iCloud data is still downloading. Try again when it is available."
                ),
                showsRetry: true
            )
        case .unavailable:
            unavailableView(
                title: String(localized: "iCloud Unavailable"),
                systemImage: "icloud.slash",
                description: String(localized: "Your iCloud account or container is not currently available."),
                showsRetry: true
            )
        case .failure:
            unavailableView(
                title: String(localized: "Unable to Load iCloud Data"),
                systemImage: "exclamationmark.triangle",
                description: String(localized: "Your synchronized data could not be safely inspected."),
                showsRetry: true
            )
        }
    }

    func inventoryList(_ loadedState: CloudDataManagementViewModel.LoadedState) -> some View {
#if os(iOS)
        List {
            inventorySections(loadedState)
        }
        .listStyle(.insetGrouped)
#else
        Form {
            inventorySections(loadedState)
        }
        .formStyle(.grouped)
#endif
    }

    @ViewBuilder
    func inventorySections(_ loadedState: CloudDataManagementViewModel.LoadedState) -> some View {
        operationSection
        ForEach(loadedState.sections) { section in
            if !section.items.isEmpty || section.failure != nil {
                categorySection(section)
            }
        }
        if loadedState.hasInventoryFailures {
            Section {
                Button(String(localized: "Retry Inventory")) {
                    viewModel.send(.retryInventoryTapped)
                }
                .disabled(viewModel.isOperationActive)
#if os(macOS)
                .buttonStyle(.bordered)
#endif
            } footer: {
                Text(String(localized: "Some categories could not be inspected and are not reported as empty."))
            }
        }
        deleteAllSection
    }

    @ViewBuilder
    var operationSection: some View {
        switch viewModel.operationState {
        case .idle:
            EmptyView()
        case .deleting:
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "Deleting synchronized data..."))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(localized: "Synchronized data deletion"))
                .accessibilityValue(String(localized: "In progress"))
            }
        case .succeeded:
            Section {
                Label(String(localized: "Synchronized data deleted"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel(String(localized: "Synchronized data deleted successfully"))
            }
        case .failed:
            Section {
                Label(
                    String(localized: "The deletion could not be completed."),
                    systemImage: "exclamationmark.triangle"
                )
                    .foregroundStyle(.red)
                retryDeletionButton
            }
        case .partiallyFailed(let categories):
            Section {
                Label(String(localized: "Some synchronized data could not be deleted."),
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                ForEach(categories) { category in
                    Text(categoryTitle(category))
                        .accessibilityLabel(String(localized: "Deletion failed for \(categoryTitle(category))"))
                }
                retryDeletionButton
            } header: {
                Text(String(localized: "Deletion Incomplete"))
            } footer: {
                Text(String(localized: "Only the listed categories failed. Retry to finish deleting them."))
            }
        }
    }

    var retryDeletionButton: some View {
        Button(String(localized: "Retry Deletion")) {
            viewModel.send(.retryDeletionTapped)
        }
        .disabled(viewModel.isOperationActive)
        .tint(.red)
#if os(macOS)
        .buttonStyle(.bordered)
#endif
    }

    func categorySection(_ section: CloudDataManagementViewModel.CategorySection) -> some View {
        Section {
            if let failure = section.failure {
                Label(inventoryFailureText(failure), systemImage: inventoryFailureImage(failure))
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(categoryTitle(section.category))
                    .accessibilityValue(inventoryFailureText(failure))
            } else {
                ForEach(visibleItems(in: section)) { item in
                    itemRow(item)
                }
                if section.items.count > 3, supportsExpansion(section.category) {
                    expansionButton(for: section)
                }
            }
        } header: {
            categoryHeader(section)
        }
    }

    @ViewBuilder
    func categoryHeader(_ section: CloudDataManagementViewModel.CategorySection) -> some View {
#if os(iOS)
        Text(categoryTitle(section.category))
#else
        HStack(spacing: 7) {
            Image(systemName: categoryImage(section.category))
                .foregroundStyle(.secondary)
            Text(categoryTitle(section.category))
            Spacer()
            if section.failure == nil {
                Text(section.items.count, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
#endif
    }

    func visibleItems(
        in section: CloudDataManagementViewModel.CategorySection
    ) -> [CloudDataManagementViewModel.Item] {
        isExpanded(section.category) ? section.items : Array(section.items.prefix(3))
    }

    func supportsExpansion(_ category: CloudDataManagementViewModel.Category) -> Bool {
        category == .conversations || category == .memory
    }

    func isExpanded(_ category: CloudDataManagementViewModel.Category) -> Bool {
        switch category {
        case .conversations: showsAllConversations
        case .memory: showsAllMemoryItems
        case .personalContext, .customTemplates: true
        }
    }

    func expansionButton(for section: CloudDataManagementViewModel.CategorySection) -> some View {
        let isExpanded = isExpanded(section.category)
        return Button {
            withAnimation(.smooth) {
                switch section.category {
                case .conversations:
                    showsAllConversations.toggle()
                case .memory:
                    showsAllMemoryItems.toggle()
                case .personalContext, .customTemplates:
                    break
                }
            }
        } label: {
            Label(
                isExpanded
                    ? String(localized: "Show Less")
                    : String(localized: "Show All (\(section.items.count))"),
                systemImage: isExpanded ? "chevron.up" : "chevron.down"
            )
        }
        .disabled(viewModel.isOperationActive)
#if os(macOS)
        .buttonStyle(.bordered)
        .controlSize(.small)
#endif
    }

    func itemRow(_ item: CloudDataManagementViewModel.Item) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body)
                    .lineLimit(item.kind == .memory ? 2 : nil)
                if case .conversation(let attachmentCount) = item.kind {
                    Text(attachmentDescription(attachmentCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(item.title)
            .accessibilityValue(itemAccessibilityValue(item))

#if os(macOS)
            Button(role: .destructive) {
                viewModel.send(.deleteRequested(item))
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.isOperationActive)
            .accessibilityLabel(String(localized: "Delete \(item.title)"))
            .accessibilityHint(String(localized: "Deletes this item from iCloud and all synchronized devices."))
            .help(String(localized: "Delete"))
#endif
        }
#if os(iOS)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                viewModel.send(.deleteRequested(item))
            } label: {
                Label(String(localized: "Delete"), systemImage: "trash")
            }
            .tint(.red)
            .disabled(viewModel.isOperationActive)
            .accessibilityHint(String(localized: "Deletes this item from iCloud and all synchronized devices."))
        }
#endif
    }

    var deleteAllSection: some View {
        Section {
            Button(role: .destructive) {
                viewModel.send(.deleteAllRequested)
            } label: {
                Label(String(localized: "Delete All Synchronized Data"), systemImage: "trash")
                    .foregroundStyle(.red)
            }
            .disabled(viewModel.isOperationActive)
#if os(macOS)
            .buttonStyle(.bordered)
#endif
        } header: {
            Text(String(localized: "All Synchronized Data"))
        } footer: {
            Text(String(localized: "This is separate from Reset App Data, which only resets local app data."))
        }
    }

    func unavailableView(
        title: String,
        systemImage: String,
        description: String,
        showsRetry: Bool
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(description)
        } actions: {
            if showsRetry {
                Button(String(localized: "Retry")) {
                    viewModel.send(.retryInventoryTapped)
                }
#if os(macOS)
                .buttonStyle(.borderedProminent)
#endif
            }
        }
    }

    var confirmationBinding: Binding<Bool> {
        Binding(
            get: { viewModel.confirmation != nil },
            set: { if !$0 { viewModel.send(.deletionCancelled) } }
        )
    }

    var confirmationTitle: String {
        guard let confirmation = viewModel.confirmation else { return String(localized: "Delete Synchronized Data?") }
        switch confirmation {
        case .item(let item):
            if item.kind == .memory {
                return String(localized: "Delete Memory Item?")
            }
            return String(localized: "Delete \(item.title)?")
        case .all:
            return String(localized: "Delete All Synchronized Data?")
        }
    }

    var confirmationMessage: String {
        guard let confirmation = viewModel.confirmation else { return "" }
        switch confirmation {
        case .item(let item):
            if case .conversation = item.kind {
                return String(localized: """
                    Deletes this conversation and its attachments from iCloud and all synchronized devices. \
                    Attachments cannot be deleted independently. This action cannot be undone.
                    """)
            }
            return String(
                localized: "Deletes this item from iCloud and all synchronized devices. This action cannot be undone."
            )
        case .all:
            return String(localized: """
                Deletes these categories from iCloud and all synchronized devices:
                - Conversations and attachments
                - Personal Context
                - Memory
                - Custom Templates

                Newer data created after this deletion can synchronize again. This action cannot be undone.
                """)
        }
    }

    func categoryTitle(_ category: CloudDataManagementViewModel.Category) -> String {
        switch category {
        case .conversations: String(localized: "Conversations")
        case .personalContext: String(localized: "Personal Context")
        case .memory: String(localized: "Memory")
        case .customTemplates: String(localized: "Custom Templates")
        }
    }

    func categoryImage(_ category: CloudDataManagementViewModel.Category) -> String {
        switch category {
        case .conversations: "bubble.left.and.bubble.right"
        case .personalContext: "person.text.rectangle"
        case .memory: "brain"
        case .customTemplates: "text.document"
        }
    }

    func inventoryFailureText(_ failure: CloudDataManagementViewModel.InventoryFailure) -> String {
        switch failure {
        case .pending: String(localized: "Waiting for iCloud download")
        case .unavailable: String(localized: "Currently unavailable")
        case .error: String(localized: "Could not be safely inspected")
        }
    }

    func inventoryFailureImage(_ failure: CloudDataManagementViewModel.InventoryFailure) -> String {
        switch failure {
        case .pending: "icloud.and.arrow.down"
        case .unavailable: "icloud.slash"
        case .error: "exclamationmark.triangle"
        }
    }

    func attachmentDescription(_ count: Int) -> String {
        count == 1 ? String(localized: "1 attachment") : String(localized: "\(count) attachments")
    }

    func itemAccessibilityValue(_ item: CloudDataManagementViewModel.Item) -> String {
        switch item.kind {
        case .conversation(let count):
            return attachmentDescription(count)
        case .profile:
            return String(localized: "Personal Context")
        case .memory:
            return String(localized: "Memory")
        case .promptTemplate:
            return String(localized: "Custom Template")
        }
    }
}

#Preview {
    NavigationStack {
        CloudDataManagementView(viewModel: CloudDataManagementViewModel(state: .loaded(.init(
            sections: [
                .init(
                    category: .conversations,
                    items: [
                        .init(id: UUID(), title: "Planning", kind: .conversation(attachmentCount: 2)),
                        .init(id: UUID(), title: "Recipes", kind: .conversation(attachmentCount: 0)),
                        .init(id: UUID(), title: "Swift", kind: .conversation(attachmentCount: 1)),
                        .init(id: UUID(), title: "Travel", kind: .conversation(attachmentCount: 3))
                    ],
                    failure: nil
                ),
                .init(
                    category: .personalContext,
                    items: [.init(id: UUID(), title: "Personal Context", kind: .profile)],
                    failure: nil
                ),
                .init(
                    category: .memory,
                    items: [
                        .init(id: UUID(), title: "Prefers concise answers", kind: .memory),
                        .init(id: UUID(), title: "Uses Swift for app development", kind: .memory),
                        .init(id: UUID(), title: "Lives in Spain", kind: .memory),
                        .init(id: UUID(), title: "Enjoys hiking", kind: .memory)
                    ],
                    failure: nil
                )
            ],
            hasInventoryFailures: false
        ))))
    }
}
