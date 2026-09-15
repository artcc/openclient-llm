//
//  ResetAppDataUseCaseTests.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class ResetAppDataUseCaseTests: XCTestCase {
    // MARK: - Properties

    private var sut: ResetAppDataUseCase!
    private var mockSettingsManager: MockSettingsManager!
    private var mockConversationRepository: MockConversationRepository!
    private var mockUserProfileManager: MockUserProfileManager!
    private var mockMemoryManager: MockMemoryManager!
    private var mockPromptTemplateRepository: MockPromptTemplateRepository!
    private var categoryOperationGate: CloudCategoryOperationGate!

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()

        mockSettingsManager = MockSettingsManager()
        mockConversationRepository = MockConversationRepository()
        mockUserProfileManager = MockUserProfileManager()
        mockMemoryManager = MockMemoryManager()
        mockPromptTemplateRepository = MockPromptTemplateRepository()
        categoryOperationGate = CloudCategoryOperationGate()
        sut = ResetAppDataUseCase(
            settingsManager: mockSettingsManager,
            conversationRepository: mockConversationRepository,
            userProfileManager: mockUserProfileManager,
            memoryManager: mockMemoryManager,
            promptTemplateRepository: mockPromptTemplateRepository,
            categoryOperationGate: categoryOperationGate,
            mutationGate: CloudSynchronizationMutationGate()
        )
    }

    override func tearDown() async throws {
        sut = nil
        mockSettingsManager = nil
        mockConversationRepository = nil
        mockUserProfileManager = nil
        mockMemoryManager = nil
        mockPromptTemplateRepository = nil
        categoryOperationGate = nil

        try await super.tearDown()
    }

    // MARK: - Tests

    func test_execute_callsDeleteAll() async throws {
        // Given
        mockSettingsManager.serverBaseURL = "https://example.com"
        mockSettingsManager.apiKey = "sk-test"

        // When
        try await sut.execute()

        // Then
        XCTAssertTrue(mockSettingsManager.deleteAllCalled)
    }

    func test_execute_deletesAllConversations() async throws {
        // Given
        let conversation = Conversation(modelId: "gpt-4")
        mockConversationRepository.conversations = [conversation]

        // When
        try await sut.execute()

        // Then
        XCTAssertTrue(mockConversationRepository.conversations.isEmpty)
        XCTAssertEqual(mockConversationRepository.cancelAndDeleteAllCallCount, 1)
    }

    func test_execute_deletesLocalProfile() async throws {
        // Given
        mockUserProfileManager.localProfile = UserProfile(name: "Test", profileDescription: "", extraInfo: "")

        // When
        try await sut.execute()

        // Then
        XCTAssertTrue(mockUserProfileManager.localProfile.isEmpty)
    }

    func test_execute_deletesOnlyCustomPromptTemplates() async throws {
        // Given
        let builtIn = PromptTemplate(title: "Built in", content: "Content", isBuiltIn: true)
        let custom = PromptTemplate(title: "Custom", content: "Content")
        mockPromptTemplateRepository.templates = [builtIn, custom]

        // When
        try await sut.execute()

        // Then
        XCTAssertEqual(mockPromptTemplateRepository.templates, [builtIn])
    }

    func test_execute_conversationDeletionFails_throwsWithoutDeletingOtherConversationData() async {
        // Given
        let expectedError = NSError(domain: "ResetAppDataUseCaseTests", code: 1)
        mockConversationRepository.deleteAllError = expectedError
        mockUserProfileManager.localProfile = UserProfile(name: "Test", profileDescription: "", extraInfo: "")
        mockMemoryManager.items = [MemoryItem(content: "Keep")]

        // When
        do {
            try await sut.execute()
            XCTFail("Expected conversation deletion failure")
        } catch {
            // Then
            XCTAssertEqual(error as NSError, expectedError)
            XCTAssertFalse(mockUserProfileManager.localProfile.isEmpty)
            XCTAssertEqual(mockMemoryManager.items.map(\.content), ["Keep"])
        }
    }

    func test_execute_memoryDeletionFails_throwsInsteadOfReportingSuccess() async {
        // Given
        let expectedError = NSError(domain: "ResetAppDataUseCaseTests", code: 2)
        mockMemoryManager.deleteAllError = expectedError
        let conversation = Conversation(modelId: "model")
        mockConversationRepository.conversations = [conversation]
        mockUserProfileManager.localProfile = UserProfile(name: "Keep")

        // When
        do {
            try await sut.execute()
            XCTFail("Expected memory deletion failure")
        } catch {
            // Then
            XCTAssertEqual(error as NSError, expectedError)
            XCTAssertEqual(mockConversationRepository.conversations, [conversation])
            XCTAssertEqual(mockUserProfileManager.localProfile.name, "Keep")
            XCTAssertFalse(mockSettingsManager.deleteAllCalled)
        }
    }

    func test_fence_nestedCategoryOperation_executesWithoutDeadlock() async throws {
        // Given
        let operationGate = try XCTUnwrap(categoryOperationGate)

        // When
        let didExecute = try await operationGate.fence {
            try await operationGate.perform {
                true
            }
        }

        // Then
        XCTAssertTrue(didExecute)
    }

    func test_execute_profileCloudOperationInFlight_waitsBeforeResettingData() async throws {
        // Given
        let operationStarted = TestAsyncGate()
        let releaseOperation = TestAsyncGate()
        let inFlightOperation = Task {
            try await categoryOperationGate.perform {
                await operationStarted.open()
                await releaseOperation.wait()
            }
        }
        await operationStarted.wait()

        // When
        let reset = Task { try await sut.execute() }
        await Task.yield()

        // Then
        XCTAssertFalse(mockSettingsManager.deleteAllCalled)
        await releaseOperation.open()
        try await inFlightOperation.value
        try await reset.value
        XCTAssertTrue(mockSettingsManager.deleteAllCalled)
    }
}
