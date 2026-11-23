//
//  CloudDataManagementViewModelTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 11/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class CloudDataManagementViewModelTests: XCTestCase {
    // MARK: - Properties

    private var useCase: MockCloudDataManagementUseCase!
    private var sut: CloudDataManagementViewModel!

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()

        useCase = MockCloudDataManagementUseCase()
        sut = CloudDataManagementViewModel(useCase: useCase)
    }

    override func tearDown() async throws {
        sut = nil
        useCase = nil

        try await super.tearDown()
    }

    // MARK: - Tests

    func test_send_viewAppeared_availableInventory_sanitizesDescriptorsAndLoadsLogicalSections() async {
        // Given
        let conversationId = UUID()
        useCase.inventoryResult = inventory(
            conversations: .available(.conversations([
                .init(id: conversationId, title: "  Plan\n\u{0000}trip  ", updatedAt: Date(), attachmentCount: 2)
            ])),
            profile: .available(.profileCount(1)),
            memory: .available(.memory([.init(
                id: UUID(),
                content: "  User prefers concise\nanswers.  ",
                updatedAt: Date()
            )])),
            templates: .available(.promptTemplates([]))
        )

        // When
        sut.send(.viewAppeared)
        await waitUntil {
            if case .loaded = self.sut.state { return true }
            return false
        }

        // Then
        guard case .loaded(let state) = sut.state else { return XCTFail("Expected loaded state") }
        XCTAssertEqual(state.sections[0].items.first?.title, "Plan trip")
        XCTAssertEqual(state.sections[0].items.first?.kind, .conversation(attachmentCount: 2))
        XCTAssertEqual(state.sections[1].items.first?.title, String(localized: "Personal Context"))
        XCTAssertEqual(state.sections[2].items.first?.title, "User prefers concise answers.")
    }

    func test_send_viewAppeared_allPending_setsPendingState() async {
        // Given
        useCase.inventoryResult = CloudDataInventory(categories: Dictionary(
            uniqueKeysWithValues: CloudDataCategory.allCases.map { ($0, .failed(.pendingDownload)) }
        ))

        // When
        sut.send(.viewAppeared)
        await waitUntil { self.sut.state == .pending }

        // Then
        XCTAssertEqual(sut.state, .pending)
    }

    func test_send_viewAppeared_allUnavailable_setsUnavailableState() async {
        // Given
        useCase.inventoryResult = CloudDataInventory(categories: Dictionary(
            uniqueKeysWithValues: CloudDataCategory.allCases.map { ($0, .failed(.unavailable)) }
        ))

        // When
        sut.send(.viewAppeared)
        await waitUntil { self.sut.state == .unavailable }

        // Then
        XCTAssertEqual(sut.state, .unavailable)
    }

    func test_send_viewAppeared_emptyInventory_setsEmptyState() async {
        // Given
        useCase.inventoryResult = emptyInventory()

        // When
        sut.send(.viewAppeared)
        await waitUntil { self.sut.state == .empty }

        // Then
        XCTAssertEqual(sut.state, .empty)
        XCTAssertEqual(useCase.calls, ["resumeDeletion", "inventory"])
    }

    func test_send_viewAppeared_onlyEmptyFolders_keepsCloudManagementAvailable() async {
        var categories = emptyInventory().categories
        categories[.conversations] = .available(.conversations([], folderCount: 2))
        useCase.inventoryResult = CloudDataInventory(categories: categories)

        sut.send(.viewAppeared)
        await waitUntil { self.sut.state != .loading }

        guard case .loaded(let state) = sut.state else { return XCTFail("Expected synchronized folders") }
        XCTAssertEqual(state.sections.first { $0.category == .conversations }?.folderCount, 2)
        sut.send(.deleteAllRequested)
        XCTAssertEqual(sut.confirmation, .all)
    }

    func test_send_viewAppeared_unfinishedDeletionSurfacesPartialResultWithEmptyInventory() async {
        // Given
        let marker = CloudPurgeMarker(id: UUID(), deletedAt: Date())
        useCase.resumeResult = CloudDeletionResult(
            marker: marker,
            outcomes: [
                .conversations: .deleted,
                .profile: .failed(.fileAccess),
                .memory: .deleted,
                .promptTemplates: .deleted
            ]
        )
        useCase.inventoryResult = emptyInventory()

        // When
        sut.send(.viewAppeared)
        await waitUntil {
            self.sut.operationState == .partiallyFailed([.personalContext])
                && self.useCase.inventoryCallCount == 1
        }

        // Then
        XCTAssertEqual(sut.operationState, .partiallyFailed([.personalContext]))
        guard case .loaded(let state) = sut.state else { return XCTFail("Expected loaded state") }
        XCTAssertTrue(state.sections.allSatisfy(\.items.isEmpty))
        XCTAssertEqual(useCase.calls, ["resumeDeletion", "inventory"])
    }

    func test_send_viewAppeared_unfinishedDeletionSurfacesPartialResultWhenInventoryUnavailable() async {
        // Given
        let marker = CloudPurgeMarker(id: UUID(), deletedAt: Date())
        useCase.resumeResult = CloudDeletionResult(
            marker: marker,
            outcomes: [.conversations: .failed(.fileAccess)]
        )
        useCase.inventoryResult = CloudDataInventory(categories: Dictionary(
            uniqueKeysWithValues: CloudDataCategory.allCases.map { ($0, .failed(.unavailable)) }
        ))

        // When
        sut.send(.viewAppeared)
        await waitUntil { self.useCase.inventoryCallCount == 1 && self.sut.state != .loading }

        // Then
        guard case .loaded(let state) = sut.state else { return XCTFail("Expected loaded state") }
        XCTAssertTrue(state.hasInventoryFailures)
        XCTAssertEqual(sut.operationState, .partiallyFailed(CloudDataManagementViewModel.Category.allCases))
    }

    func test_send_retryDeletionTapped_resumedPartialDeletionRetriesAndRefreshesInventory() async {
        // Given
        let marker = CloudPurgeMarker(id: UUID(), deletedAt: Date())
        useCase.resumeResult = CloudDeletionResult(
            marker: marker,
            outcomes: [.profile: .failed(.fileAccess)]
        )
        useCase.retryResult = CloudDeletionResult(
            marker: marker,
            outcomes: Dictionary(uniqueKeysWithValues: CloudDataCategory.allCases.map {
                ($0, CloudDeletionCategoryOutcome.deleted)
            })
        )
        useCase.inventoryResult = emptyInventory()
        sut.send(.viewAppeared)
        await waitUntil {
            if case .partiallyFailed = self.sut.operationState { return true }
            return false
        }

        // When
        sut.send(.retryDeletionTapped)
        await waitUntil { self.useCase.retryCallCount == 1 && self.sut.state == .empty }

        // Then
        XCTAssertEqual(sut.operationState, .succeeded)
        XCTAssertEqual(useCase.inventoryCallCount, 2)
    }

    func test_send_retryDeletionTapped_resumeFailureRetriesResumeBeforeRefreshingInventory() async {
        // Given
        useCase.resumeError = CocoaError(.fileReadUnknown)
        useCase.inventoryResult = emptyInventory()
        sut.send(.viewAppeared)
        await waitUntil { self.sut.operationState == .failed && self.useCase.inventoryCallCount == 1 }
        useCase.resumeError = nil

        // When
        sut.send(.retryDeletionTapped)
        await waitUntil { self.useCase.resumeCallCount == 2 && self.useCase.inventoryCallCount == 2 }

        // Then
        XCTAssertEqual(sut.operationState, .idle)
        XCTAssertEqual(sut.state, .empty)
        XCTAssertEqual(useCase.calls, ["resumeDeletion", "inventory", "resumeDeletion", "inventory"])
    }

    func test_send_retryInventoryTapped_afterFailure_reloadsInventory() async {
        // Given
        useCase.inventoryResult = CloudDataInventory(categories: Dictionary(
            uniqueKeysWithValues: CloudDataCategory.allCases.map { ($0, .failed(.fileAccess)) }
        ))
        sut.send(.viewAppeared)
        await waitUntil { self.sut.state == .failure }
        useCase.inventoryResult = emptyInventory()

        // When
        sut.send(.retryInventoryTapped)
        await waitUntil { self.sut.state == .empty }

        // Then
        XCTAssertEqual(sut.state, .empty)
    }

    func test_send_deletionConfirmed_conversation_deletesItemAndReloadsInventory() async {
        // Given
        let item = CloudDataManagementViewModel.Item(
            id: UUID(),
            title: "Conversation",
            kind: .conversation(attachmentCount: 3)
        )
        useCase.inventoryResult = emptyInventory()
        sut.send(.deleteRequested(item))

        // When
        sut.send(.deletionConfirmed)
        await waitUntil { self.useCase.deletedConversationId != nil && self.sut.state == .empty }

        // Then
        XCTAssertEqual(useCase.deletedConversationId, item.id)
        XCTAssertEqual(sut.operationState, .succeeded)
        XCTAssertEqual(sut.state, .empty)
    }

    func test_send_deletionCancelled_pendingRequest_clearsConfirmationWithoutDeleting() {
        // Given
        let item = CloudDataManagementViewModel.Item(id: UUID(), title: "Memory Item", kind: .memory)
        sut.send(.deleteRequested(item))

        // When
        sut.send(.deletionCancelled)

        // Then
        XCTAssertNil(sut.confirmation)
        XCTAssertNil(useCase.deletedMemoryId)
    }

    func test_send_deletionConfirmed_partialDelete_listsFailuresAndDoesNotReportSuccess() async {
        // Given
        let marker = CloudPurgeMarker(id: UUID(), deletedAt: Date())
        useCase.deletionResult = CloudDeletionResult(
            marker: marker,
            outcomes: [
                .conversations: .deleted,
                .profile: .failed(.fileAccess),
                .memory: .deleted,
                .promptTemplates: .failed(.pendingDownload)
            ]
        )
        sut.send(.deleteAllRequested)

        // When
        sut.send(.deletionConfirmed)
        await waitUntil {
            self.sut.operationState == .partiallyFailed([.personalContext, .customTemplates])
        }

        // Then
        XCTAssertEqual(sut.operationState, .partiallyFailed([.personalContext, .customTemplates]))
        XCTAssertNotEqual(sut.operationState, .succeeded)
    }

    func test_send_retryDeletionTapped_partialDeleteRetriesOnlyThroughUseCase() async {
        // Given
        let marker = CloudPurgeMarker(id: UUID(), deletedAt: Date())
        useCase.deletionResult = CloudDeletionResult(
            marker: marker,
            outcomes: [.profile: .failed(.fileAccess)]
        )
        useCase.retryResult = CloudDeletionResult(
            marker: marker,
            outcomes: Dictionary(uniqueKeysWithValues: CloudDataCategory.allCases.map {
                ($0, CloudDeletionCategoryOutcome.deleted)
            })
        )
        useCase.inventoryResult = emptyInventory()
        sut.send(.deleteAllRequested)
        sut.send(.deletionConfirmed)
        await waitUntil {
            if case .partiallyFailed = self.sut.operationState { return true }
            return false
        }

        // When
        sut.send(.retryDeletionTapped)
        await waitUntil { self.useCase.retryCallCount == 1 && self.sut.state == .empty }

        // Then
        XCTAssertEqual(sut.operationState, .succeeded)
        XCTAssertEqual(sut.state, .empty)
    }

    // MARK: - Private

    private func inventory(
        conversations: CloudInventoryCategoryResult,
        profile: CloudInventoryCategoryResult,
        memory: CloudInventoryCategoryResult,
        templates: CloudInventoryCategoryResult
    ) -> CloudDataInventory {
        CloudDataInventory(categories: [
            .conversations: conversations,
            .profile: profile,
            .memory: memory,
            .promptTemplates: templates
        ])
    }

    private func emptyInventory() -> CloudDataInventory {
        inventory(
            conversations: .available(.conversations([])),
            profile: .available(.profileCount(0)),
            memory: .available(.memory([])),
            templates: .available(.promptTemplates([]))
        )
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<100 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Condition was not satisfied", file: file, line: line)
    }
}
