//
//  ModelsViewModelSTTTests.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 02/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class ModelsViewModelSTTTests: XCTestCase {
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

    // MARK: - Tests — sttModelTapped

    func test_send_sttModelTapped_updatesSelectedSTTModelId() async throws {
        // Given
        let sttModel = LLMModel(id: "whisper-1", mode: .audioTranscription)
        mockFetchModels.result = .success([LLMModel(id: "gpt-4"), sttModel])

        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        // When
        sut.send(.sttModelTapped(sttModel))

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.selectedSTTModelId, "whisper-1")
    }

    func test_send_sttModelTapped_doesNotAffectChatModelId() async throws {
        // Given
        let chatModel = LLMModel(id: "gpt-4")
        let sttModel = LLMModel(id: "whisper-1", mode: .audioTranscription)
        mockFetchModels.result = .success([chatModel, sttModel])
        mockSettingsManager.selectedModelId = "gpt-4"

        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        // When
        sut.send(.sttModelTapped(sttModel))

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.selectedSTTModelId, "whisper-1")
        XCTAssertEqual(loadedState.selectedModelId, "gpt-4")
    }

    func test_send_sttModelTapped_persistsViaSettingsManager() async throws {
        // Given
        let sttModel = LLMModel(id: "whisper-large", mode: .audioTranscription)
        mockFetchModels.result = .success([sttModel])

        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        // When
        sut.send(.sttModelTapped(sttModel))

        // Then
        XCTAssertEqual(mockSettingsManager.selectedSTTModelId, "whisper-large")
    }

    func test_send_modelTapped_doesNotAffectSTTModelId() async throws {
        // Given
        let chatModel = LLMModel(id: "gpt-4")
        let sttModel = LLMModel(id: "whisper-1", mode: .audioTranscription)
        mockFetchModels.result = .success([chatModel, sttModel])
        mockSettingsManager.selectedSTTModelId = "whisper-1"

        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        // When
        sut.send(.modelTapped(chatModel))

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.selectedModelId, "gpt-4")
        XCTAssertEqual(loadedState.selectedSTTModelId, "whisper-1")
    }

    func test_viewAppeared_loadsSelectedSTTModelId() async throws {
        // Given
        mockSettingsManager.selectedSTTModelId = "whisper-1"
        let sttModel = LLMModel(id: "whisper-1", mode: .audioTranscription)
        mockFetchModels.result = .success([sttModel])

        // When
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.selectedSTTModelId, "whisper-1")
    }

    func test_send_sttModelTapped_doesNotAffectTTSModelId() async throws {
        // Given
        let ttsModel = LLMModel(id: "tts-1", mode: .audioSpeech)
        let sttModel = LLMModel(id: "whisper-1", mode: .audioTranscription)
        mockFetchModels.result = .success([ttsModel, sttModel])
        mockSettingsManager.selectedTTSModelId = "tts-1"

        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        // When
        sut.send(.sttModelTapped(sttModel))

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.selectedSTTModelId, "whisper-1")
        XCTAssertEqual(loadedState.selectedTTSModelId, "tts-1")
    }

    // MARK: - Tests — Apple STT default

    func test_viewAppeared_appleSTTAlwaysInList() async throws {
        // Given — sin modelos STT de LiteLLM
        mockFetchModels.result = .success([LLMModel(id: "gpt-4")])

        // When
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        // Then — Apple sentinel siempre presente
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        let sttModels = loadedState.models.filter { $0.mode == .audioTranscription }
        XCTAssertTrue(sttModels.contains(where: { $0.id == LLMModel.appleSpeechRecognition.id }))
    }

    func test_viewAppeared_appleSTTSelectedByDefault() async throws {
        // Given — sin STT guardado en settings, sin modelos LiteLLM
        mockFetchModels.result = .success([LLMModel(id: "gpt-4")])

        // When
        sut.send(.viewAppeared)
        try await Task.sleep(for: .milliseconds(100))

        // Then — Apple seleccionado por defecto
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.selectedSTTModelId, LLMModel.appleSpeechRecognition.id)
        XCTAssertEqual(mockSettingsManager.selectedSTTModelId, LLMModel.appleSpeechRecognition.id)
    }

    func test_refreshAsync_noSelectionWithRemoteSTT_selectsAndPersistsApple() async {
        // Given
        mockFetchModels.result = .success([LLMModel(id: "whisper-1", mode: .audioTranscription)])
        sut = ModelsViewModel(
            state: .loaded(.init()),
            fetchModelsUseCase: mockFetchModels,
            settingsManager: mockSettingsManager
        )

        // When
        await sut.refreshAsync()

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.selectedSTTModelId, LLMModel.appleSpeechRecognition.id)
        XCTAssertEqual(mockSettingsManager.selectedSTTModelId, LLMModel.appleSpeechRecognition.id)
    }

    func test_refreshAsync_onlyAppleAvailable_selectsAndPersistsApple() async {
        // Given
        let sttModel = LLMModel(id: "whisper-1", mode: .audioTranscription)
        mockSettingsManager.selectedSTTModelId = sttModel.id
        mockFetchModels.result = .success([LLMModel(id: "gpt-4")])
        sut = ModelsViewModel(
            state: .loaded(.init(models: [sttModel], selectedSTTModelId: sttModel.id)),
            fetchModelsUseCase: mockFetchModels,
            settingsManager: mockSettingsManager
        )

        // When
        await sut.refreshAsync()

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.selectedSTTModelId, LLMModel.appleSpeechRecognition.id)
        XCTAssertEqual(mockSettingsManager.selectedSTTModelId, LLMModel.appleSpeechRecognition.id)
    }

    func test_refreshAsync_selectedSTTStillAvailable_preservesSelection() async {
        // Given
        let sttModel = LLMModel(id: "whisper-1", mode: .audioTranscription)
        mockSettingsManager.selectedSTTModelId = sttModel.id
        mockFetchModels.result = .success([sttModel])
        sut = ModelsViewModel(
            state: .loaded(.init(models: [sttModel], selectedSTTModelId: sttModel.id)),
            fetchModelsUseCase: mockFetchModels,
            settingsManager: mockSettingsManager
        )

        // When
        await sut.refreshAsync()

        // Then
        guard case .loaded(let loadedState) = sut.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(loadedState.selectedSTTModelId, sttModel.id)
        XCTAssertEqual(mockSettingsManager.selectedSTTModelId, sttModel.id)
    }
}
