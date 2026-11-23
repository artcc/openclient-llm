//
//  CloudDataManagementViewModel.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 11/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

@Observable
@MainActor
final class CloudDataManagementViewModel {
    enum Event {
        case viewAppeared
        case retryInventoryTapped
        case deleteRequested(Item)
        case deleteAllRequested
        case deletionCancelled
        case deletionConfirmed
        case retryDeletionTapped
    }

    enum State: Equatable {
        case loading
        case loaded(LoadedState)
        case empty
        case pending
        case unavailable
        case failure
    }

    struct LoadedState: Equatable {
        let sections: [CategorySection]
        let hasInventoryFailures: Bool
    }

    struct CategorySection: Identifiable, Equatable {
        let category: Category
        let items: [Item]
        let failure: InventoryFailure?
        var folderCount = 0

        var id: Category { category }
        var hasContent: Bool { !items.isEmpty || folderCount > 0 }
    }

    enum ItemKind: Equatable {
        case conversation(attachmentCount: Int)
        case profile
        case memory
        case promptTemplate
    }

    struct Item: Identifiable, Equatable {
        let id: UUID
        let title: String
        let kind: ItemKind
    }

    enum Category: Int, CaseIterable, Equatable, Identifiable {
        case conversations
        case personalContext
        case memory
        case customTemplates

        var id: Int { rawValue }
    }

    enum InventoryFailure: Equatable {
        case pending
        case unavailable
        case error
    }

    enum DeletionRequest: Equatable {
        case item(Item)
        case all
    }

    enum OperationState: Equatable {
        case idle
        case deleting
        case succeeded
        case failed
        case partiallyFailed([Category])
    }

    // MARK: - Properties

    private(set) var state: State
    private(set) var confirmation: DeletionRequest?
    private(set) var operationState: OperationState = .idle

    var isOperationActive: Bool { operationState == .deleting }

    private let useCase: CloudDataManagementUseCaseProtocol
    private var task: Task<Void, Never>?
    private var failedRequest: DeletionRequest?
    private var partialDeletionResult: CloudDeletionResult?
    private var resumeDeletionFailed = false

    // MARK: - Init

    init(
        state: State = .loading,
        useCase: CloudDataManagementUseCaseProtocol = CloudDataManagementUseCase()
    ) {
        self.state = state
        self.useCase = useCase
    }

    // MARK: - Input

    func send(_ event: Event) {
        switch event {
        case .viewAppeared:
            handleViewAppeared()
        case .retryInventoryTapped:
            loadInventory()
        case .deleteRequested(let item):
            requestDeletion(.item(item))
        case .deleteAllRequested:
            requestDeletion(.all)
        case .deletionCancelled:
            confirmation = nil
        case .deletionConfirmed:
            confirmDeletion()
        case .retryDeletionTapped:
            retryDeletion()
        }
    }
}

// MARK: - Private

private extension CloudDataManagementViewModel {
    func handleViewAppeared() {
        guard state == .loading else { return }
        resumeDeletionAndLoadInventory()
    }

    func requestDeletion(_ request: DeletionRequest) {
        guard !isOperationActive else { return }
        confirmation = request
    }

    func confirmDeletion() {
        guard let confirmation, !isOperationActive else { return }
        self.confirmation = nil
        performDeletion(confirmation)
    }

    func loadInventory(showsLoading: Bool = true) {
        guard !isOperationActive else { return }
        task?.cancel()
        if showsLoading { state = .loading }
        task = Task { [weak self] in
            guard let self else { return }
            let inventory = await useCase.inventory()
            guard !Task.isCancelled else { return }
            state = makeState(from: inventory)
            task = nil
        }
    }

    func resumeDeletionAndLoadInventory(showsLoading: Bool = true) {
        guard !isOperationActive else { return }
        task?.cancel()
        if showsLoading { state = .loading }
        operationState = .deleting
        task = Task { [weak self] in
            guard let self else { return }
            do {
                if let result = try await useCase.resumeDeletion() {
                    resumeDeletionFailed = false
                    handleDeletionResult(result, request: .all)
                } else {
                    resumeDeletionFailed = false
                    operationState = .idle
                }
            } catch {
                resumeDeletionFailed = true
                operationState = .failed
            }
            let inventory = await useCase.inventory()
            guard !Task.isCancelled else { return }
            state = makeState(from: inventory)
            task = nil
        }
    }

    func performDeletion(_ request: DeletionRequest) {
        operationState = .deleting
        failedRequest = nil
        partialDeletionResult = nil
        task = Task { [weak self] in
            guard let self else { return }
            do {
                switch request {
                case .item(let item):
                    try await delete(item)
                    operationState = .succeeded
                    await reloadInventoryAfterDeletion()
                case .all:
                    let result = try await useCase.deleteAll()
                    handleDeletionResult(result, request: request)
                    if operationState == .succeeded {
                        await reloadInventoryAfterDeletion()
                    }
                }
            } catch {
                failedRequest = request
                operationState = .failed
            }
            task = nil
        }
    }

    func retryDeletion() {
        guard !isOperationActive else { return }
        if let partialDeletionResult {
            operationState = .deleting
            task = Task { [weak self] in
                guard let self else { return }
                do {
                    let result = try await useCase.retryDeletion(partialDeletionResult)
                    handleDeletionResult(result, request: .all)
                    if operationState == .succeeded {
                        await reloadInventoryAfterDeletion()
                    }
                } catch {
                    operationState = .partiallyFailed(categories(for: partialDeletionResult.failedCategories))
                }
                task = nil
            }
        } else if resumeDeletionFailed {
            resumeDeletionAndLoadInventory(showsLoading: false)
        } else if let failedRequest {
            performDeletion(failedRequest)
        }
    }

    func delete(_ item: Item) async throws {
        switch item.kind {
        case .conversation:
            try await useCase.deleteConversation(id: item.id)
        case .profile:
            try await useCase.deleteProfile()
        case .memory:
            try await useCase.deleteMemory(id: item.id)
        case .promptTemplate:
            try await useCase.deletePromptTemplate(id: item.id)
        }
    }

    func handleDeletionResult(_ result: CloudDeletionResult, request: DeletionRequest) {
        var outcomes = result.outcomes
        for category in CloudDataCategory.allCases where outcomes[category] == nil {
            outcomes[category] = .failed(.fileAccess)
        }
        let normalizedResult = CloudDeletionResult(marker: result.marker, outcomes: outcomes)
        let failedCategories = categories(for: normalizedResult.failedCategories)
        guard failedCategories.isEmpty else {
            partialDeletionResult = normalizedResult
            failedRequest = request
            operationState = .partiallyFailed(failedCategories)
            return
        }
        partialDeletionResult = nil
        failedRequest = nil
        operationState = .succeeded
    }

    func reloadInventoryAfterDeletion() async {
        let inventory = await useCase.inventory()
        guard !Task.isCancelled else { return }
        state = makeState(from: inventory)
    }

    func makeState(from inventory: CloudDataInventory) -> State {
        let sections = Category.allCases.map { makeSection($0, inventory: inventory) }
        let failures = sections.compactMap(\.failure)
        let hasItems = sections.contains(where: \.hasContent)
        let hasUnfinishedDeletion: Bool
        switch operationState {
        case .failed, .partiallyFailed:
            hasUnfinishedDeletion = true
        case .idle, .deleting, .succeeded:
            hasUnfinishedDeletion = false
        }
        if hasUnfinishedDeletion {
            return .loaded(.init(sections: sections, hasInventoryFailures: !failures.isEmpty))
        }
        guard !failures.isEmpty else {
            return hasItems ? .loaded(.init(sections: sections, hasInventoryFailures: false)) : .empty
        }
        if failures.count == Category.allCases.count {
            if failures.allSatisfy({ $0 == .pending }) { return .pending }
            if failures.allSatisfy({ $0 == .unavailable }) { return .unavailable }
            return .failure
        }
        return .loaded(.init(sections: sections, hasInventoryFailures: true))
    }

    func makeSection(_ category: Category, inventory: CloudDataInventory) -> CategorySection {
        let cloudCategory = cloudCategory(for: category)
        guard let result = inventory.categories[cloudCategory] else {
            return .init(category: category, items: [], failure: .error)
        }
        switch result {
        case .failed(let failure):
            return .init(category: category, items: [], failure: presentationFailure(for: failure))
        case .available(let value):
            guard let items = items(for: category, value: value) else {
                return .init(category: category, items: [], failure: .error)
            }
            var section = CategorySection(category: category, items: items, failure: nil)
            if case .conversations(_, let folderCount) = value { section.folderCount = folderCount }
            return section
        }
    }

    func items(for category: Category, value: CloudInventoryCategoryValue) -> [Item]? {
        switch (category, value) {
        case (.conversations, .conversations(let conversations, _)):
            return conversations.map {
                Item(
                    id: $0.id,
                    title: sanitized($0.title, fallback: String(localized: "Untitled Conversation")),
                    kind: .conversation(attachmentCount: max(0, $0.attachmentCount))
                )
            }
        case (.personalContext, .profileCount(let count)):
            return count > 0
                ? [Item(id: UUID.zero, title: String(localized: "Personal Context"), kind: .profile)]
                : []
        case (.memory, .memory(let memoryItems)):
            return memoryItems.enumerated().map { index, item in
                Item(
                    id: item.id,
                    title: sanitized(item.content, fallback: String(localized: "Memory Item \(index + 1)")),
                    kind: .memory
                )
            }
        case (.customTemplates, .promptTemplates(let templates)):
            return templates.map {
                Item(
                    id: $0.id,
                    title: sanitized($0.title, fallback: String(localized: "Untitled Template")),
                    kind: .promptTemplate
                )
            }
        default:
            return nil
        }
    }

    func sanitized(_ value: String, fallback: String) -> String {
        let visibleValue = value.unicodeScalars.map {
            CharacterSet.controlCharacters.contains($0) ? " " : String($0)
        }.joined()
        let normalized = visibleValue
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        guard !normalized.isEmpty else { return fallback }
        return String(normalized.prefix(100))
    }

    func presentationFailure(for failure: CloudInventoryFailure) -> InventoryFailure {
        switch failure {
        case .pendingDownload:
            return .pending
        case .unavailable:
            return .unavailable
        case .unsupportedSchema, .corruptData, .fileAccess:
            return .error
        }
    }

    func cloudCategory(for category: Category) -> CloudDataCategory {
        switch category {
        case .conversations: .conversations
        case .personalContext: .profile
        case .memory: .memory
        case .customTemplates: .promptTemplates
        }
    }

    func categories(for cloudCategories: Set<CloudDataCategory>) -> [Category] {
        Category.allCases.filter { cloudCategories.contains(cloudCategory(for: $0)) }
    }
}

private extension UUID {
    static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}
