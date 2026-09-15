//
//  ModelsViewModelTests.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class ModelsViewModelTests: XCTestCase {
    // MARK: - Properties

    private var sut: ModelsViewModel!
    private var mockFetchModels: MockFetchModelsUseCase!
    private var mockSettingsManager: MockSettingsManager!

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()

        mockFetchModels = MockFetchModelsUseCase()
        mockSettingsManager = MockSettingsManager()
        sut = ModelsViewModel(
            fetchModelsUseCase: mockFetchModels,
            settingsManager: mockSettingsManager
        )
    }

    override func tearDown() async throws {
        sut = nil
        mockFetchModels = nil
        mockSettingsManager = nil

        try await super.tearDown()
    }

    // MARK: - Tests — Init

    func test_init_defaultState_isLoading() {
        // Then
        XCTAssertEqual(sut.state, .loading)
    }

    // MARK: - Tests — viewAppeared

    func test_send_viewAppeared_withModels_setsLoadedState() async throws {
        // Given
        let models = [LLMModel(id: "gpt-4"), LLMModel(id: "llama3")]
        mockFetchModels.result = .success(models)

        // When
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.models.count, 3) // 2 chat models + Apple STT sentinel
        XCTAssertNil(loadedState.errorMessage)
    }

    func test_send_viewAppeared_withError_setsErrorMessage() async throws {
        // Given
        mockFetchModels.result = .failure(APIError.serverUnreachable)

        // When
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertTrue(loadedState.models.isEmpty)
        XCTAssertNotNil(loadedState.errorMessage)
    }

    func test_send_viewAppeared_repeatedly_fetchesModelsOnce() async throws {
        // Given
        var executeCount = 0
        mockFetchModels.onExecute = { executeCount += 1 }

        // When
        sut.send(.viewAppeared)
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        // Then
        XCTAssertEqual(executeCount, 1)
    }

    // MARK: - Tests — refreshTapped

    func test_send_refreshTapped_reloadsModels() async throws {
        // Given
        mockFetchModels.result = .success([LLMModel(id: "gpt-4")])
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        let updatedModels = [LLMModel(id: "gpt-4"), LLMModel(id: "claude-3")]
        mockFetchModels.result = .success(updatedModels)

        // When
        sut.send(.refreshTapped)
        try await Task.sleep(for: .milliseconds(100))

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.models.count, 3) // 2 updated models + Apple STT sentinel
    }

    // MARK: - Tests — modelTapped

    func test_send_modelTapped_updatesSelectedModelId() async throws {
        // Given
        let models = [LLMModel(id: "gpt-4"), LLMModel(id: "llama3")]
        mockFetchModels.result = .success(models)
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        // When
        sut.send(.modelTapped(models[0]))

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.selectedModelId, "gpt-4")
    }

    func test_send_modelTapped_persistsSelection() async throws {
        // Given
        let models = [LLMModel(id: "gpt-4")]
        mockFetchModels.result = .success(models)
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        // When
        sut.send(.modelTapped(models[0]))

        // Then
        XCTAssertEqual(mockSettingsManager.selectedModelId, "gpt-4")
    }

    func test_send_viewAppeared_loadsSelectedModelId() async throws {
        // Given
        mockSettingsManager.selectedModelId = "llama3"
        let models = [LLMModel(id: "gpt-4"), LLMModel(id: "llama3")]
        mockFetchModels.result = .success(models)

        // When
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.selectedModelId, "llama3")
    }
}
