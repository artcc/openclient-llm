//
//  ModelsViewModelImageAndVisionTests.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Observation
import XCTest
@testable import openclient_llm

@MainActor
final class ModelsViewModelImageAndVisionTests: XCTestCase {
    // MARK: - Properties

    private var sut: ModelsViewModel!
    private var mockFetchModels: MockFetchModelsUseCase!
    private var mockSettings: MockSettingsManager!
    private let models = [
        LLMModel(id: "chat"),
        LLMModel(id: "vision", capabilities: [.vision]),
        LLMModel(id: "images", mode: .imageGeneration),
        LLMModel(id: "dual", capabilities: [.vision, .imageGeneration]),
        LLMModel(id: "unsupported", capabilities: [.vision, .imageGeneration], mode: .embedding)
    ]

    private var loadedState: ModelsViewModel.LoadedState? {
        guard case .loaded(let state) = sut.state else { return nil }
        return state
    }

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()

        mockFetchModels = MockFetchModelsUseCase()
        mockFetchModels.result = .success(models)
        mockSettings = MockSettingsManager()
        mockSettings.selectedModelId = "chat"
        mockSettings.selectedTTSModelId = "speech"
        mockSettings.selectedSTTModelId = "transcription"
        sut = ModelsViewModel(
            state: .loaded(.init(
                models: models,
                selectedModelId: "chat",
                selectedTTSModelId: "speech",
                selectedSTTModelId: "transcription"
            )),
            fetchModelsUseCase: mockFetchModels,
            settingsManager: mockSettings
        )
    }

    override func tearDown() async throws {
        sut = nil
        mockFetchModels = nil
        mockSettings = nil

        try await super.tearDown()
    }
}

// MARK: - Tests - Loading

extension ModelsViewModelImageAndVisionTests {
    func test_viewAppeared_noSavedSelections_doesNotChooseDefaults() async throws {
        // Given
        XCTAssertNil(mockSettings.selectedVisionModelId)
        XCTAssertNil(mockSettings.selectedImageGenerationModelId)

        // When
        await loadOnAppearance()

        // Then
        let state = try XCTUnwrap(loadedState)
        XCTAssertNil(state.selectedVisionModelId)
        XCTAssertNil(state.selectedImageGenerationModelId)
        XCTAssertNil(mockSettings.selectedVisionModelId)
        XCTAssertNil(mockSettings.selectedImageGenerationModelId)
        XCTAssertFalse(state.isSelectedVisionModelUnavailable)
        XCTAssertFalse(state.isSelectedImageModelUnavailable)
    }

    func test_viewAppeared_savedSelections_loadsIndependentIds() async throws {
        // Given
        mockSettings.selectedVisionModelId = "vision"
        mockSettings.selectedImageGenerationModelId = "images"

        // When
        await loadOnAppearance()

        // Then
        let state = try XCTUnwrap(loadedState)
        XCTAssertEqual(state.selectedVisionModelId, "vision")
        XCTAssertEqual(state.selectedImageGenerationModelId, "images")
        XCTAssertFalse(state.isSelectedVisionModelUnavailable)
        XCTAssertFalse(state.isSelectedImageModelUnavailable)
    }

    func test_viewAppeared_savedModelsMissing_keepsIdsUnavailable() async throws {
        // Given
        mockSettings.selectedVisionModelId = "missing-vision"
        mockSettings.selectedImageGenerationModelId = "missing-images"

        // When
        await loadOnAppearance()

        // Then
        let state = try XCTUnwrap(loadedState)
        XCTAssertEqual(state.selectedVisionModelId, "missing-vision")
        XCTAssertEqual(state.selectedImageGenerationModelId, "missing-images")
        XCTAssertTrue(state.isSelectedVisionModelUnavailable)
        XCTAssertTrue(state.isSelectedImageModelUnavailable)
        XCTAssertEqual(mockSettings.selectedVisionModelId, "missing-vision")
        XCTAssertEqual(mockSettings.selectedImageGenerationModelId, "missing-images")
    }

    func test_viewAppeared_fetchFails_keepsSavedSelections() async throws {
        // Given
        mockSettings.selectedVisionModelId = "vision"
        mockSettings.selectedImageGenerationModelId = "images"
        mockFetchModels.result = .failure(APIError.serverUnreachable)

        // When
        await loadOnAppearance()

        // Then
        let state = try XCTUnwrap(loadedState)
        XCTAssertNotNil(state.errorMessage)
        XCTAssertEqual(state.selectedVisionModelId, "vision")
        XCTAssertEqual(state.selectedImageGenerationModelId, "images")
        XCTAssertEqual(mockSettings.selectedVisionModelId, "vision")
        XCTAssertEqual(mockSettings.selectedImageGenerationModelId, "images")
    }

}

// MARK: - Tests - Selection and refresh

extension ModelsViewModelImageAndVisionTests {
    func test_send_validSelections_updatesOnlyImageAndVisionDefaults() throws {
        // Given
        var expected = try XCTUnwrap(loadedState)
        expected.selectedVisionModelId = "vision"
        expected.selectedImageGenerationModelId = "images"

        // When
        sut.send(.visionModelSelected("vision"))
        sut.send(.imageGenerationModelSelected("images"))

        // Then
        XCTAssertEqual(sut.state, .loaded(expected))
        XCTAssertEqual(mockSettings.selectedVisionModelId, "vision")
        XCTAssertEqual(mockSettings.selectedImageGenerationModelId, "images")
        XCTAssertEqual(mockSettings.selectedModelId, "chat")
        XCTAssertEqual(mockSettings.selectedTTSModelId, "speech")
        XCTAssertEqual(mockSettings.selectedSTTModelId, "transcription")
    }

    func test_send_noneForVision_clearsOnlyVision() throws {
        // Given
        sut.send(.visionModelSelected("vision"))
        sut.send(.imageGenerationModelSelected("images"))
        var expected = try XCTUnwrap(loadedState)
        expected.selectedVisionModelId = nil

        // When
        sut.send(.visionModelSelected(nil))

        // Then
        XCTAssertEqual(sut.state, .loaded(expected))
        XCTAssertNil(mockSettings.selectedVisionModelId)
        XCTAssertEqual(mockSettings.selectedImageGenerationModelId, "images")
    }

    func test_send_noneForImageGeneration_clearsOnlyImageGeneration() throws {
        // Given
        sut.send(.visionModelSelected("vision"))
        sut.send(.imageGenerationModelSelected("images"))
        var expected = try XCTUnwrap(loadedState)
        expected.selectedImageGenerationModelId = nil

        // When
        sut.send(.imageGenerationModelSelected(nil))

        // Then
        XCTAssertEqual(sut.state, .loaded(expected))
        XCTAssertEqual(mockSettings.selectedVisionModelId, "vision")
        XCTAssertNil(mockSettings.selectedImageGenerationModelId)
    }

    func test_send_invalidSelections_rejectsMissingIdsAndWrongCapabilities() {
        // Given
        sut.send(.visionModelSelected("vision"))
        sut.send(.imageGenerationModelSelected("images"))
        let previousState = sut.state
        let invalidEvents: [ModelsViewModel.Event] = [
            .visionModelSelected("missing"), .visionModelSelected(""),
            .visionModelSelected("images"), .visionModelSelected("chat"),
            .imageGenerationModelSelected("missing"), .imageGenerationModelSelected(""),
            .imageGenerationModelSelected("vision"), .imageGenerationModelSelected("chat"),
            .visionModelSelected("unsupported"), .imageGenerationModelSelected("unsupported")
        ]

        // When
        for event in invalidEvents {
            sut.send(event)

            // Then
            XCTAssertEqual(sut.state, previousState)
            XCTAssertEqual(mockSettings.selectedVisionModelId, "vision")
            XCTAssertEqual(mockSettings.selectedImageGenerationModelId, "images")
        }
    }

    func test_send_loading_ignoresSelectionsAndNone() {
        // Given
        mockSettings.selectedVisionModelId = "vision"
        mockSettings.selectedImageGenerationModelId = "images"
        sut = ModelsViewModel(fetchModelsUseCase: mockFetchModels, settingsManager: mockSettings)

        // When
        sut.send(.visionModelSelected("dual"))
        sut.send(.imageGenerationModelSelected("dual"))
        sut.send(.visionModelSelected(nil))
        sut.send(.imageGenerationModelSelected(nil))

        // Then
        XCTAssertEqual(sut.state, .loading)
        XCTAssertEqual(mockSettings.selectedVisionModelId, "vision")
        XCTAssertEqual(mockSettings.selectedImageGenerationModelId, "images")
    }

    func test_send_dualCapabilityModel_allowsBothSpecialistRolesViaChatTransport() throws {
        // Given
        let model = try XCTUnwrap(models.first { $0.id == "dual" })

        // When
        sut.send(.visionModelSelected(model.id))
        sut.send(.imageGenerationModelSelected(model.id))
        sut.send(.modelTapped(model))

        // Then
        let state = try XCTUnwrap(loadedState)
        XCTAssertEqual(state.selectedVisionModelId, model.id)
        XCTAssertEqual(state.selectedImageGenerationModelId, model.id)
        XCTAssertEqual(state.selectedModelId, model.id)
        XCTAssertEqual(mockSettings.selectedVisionModelId, model.id)
        XCTAssertEqual(mockSettings.selectedImageGenerationModelId, model.id)
        XCTAssertEqual(state.models, models)
        XCTAssertEqual(state.visionModels.map(\.id), ["vision", "dual"])
        XCTAssertEqual(state.imageGenerationModels.map(\.id), ["images", "dual"])
        XCTAssertFalse(state.isSelectedVisionSpecialistUnsupported)
        XCTAssertFalse(state.isSelectedImageSpecialistUnsupported)
        XCTAssertFalse(state.isSelectedImageModelUnavailable)
    }

    func test_viewAppeared_savedUnsupportedMode_keepsIdsUnavailableAndExcludesOptions() async throws {
        // Given
        mockSettings.selectedVisionModelId = "unsupported"
        mockSettings.selectedImageGenerationModelId = "unsupported"

        // When
        await loadOnAppearance()

        // Then
        let state = try XCTUnwrap(loadedState)
        XCTAssertEqual(state.visionModels.map(\.id), ["vision", "dual"])
        XCTAssertEqual(state.imageGenerationModels.map(\.id), ["images", "dual"])
        XCTAssertEqual(state.selectedVisionModelId, "unsupported")
        XCTAssertEqual(state.selectedImageGenerationModelId, "unsupported")
        XCTAssertTrue(state.isSelectedVisionModelUnavailable)
        XCTAssertTrue(state.isSelectedImageModelUnavailable)
        XCTAssertTrue(state.isSelectedVisionSpecialistUnsupported)
        XCTAssertTrue(state.isSelectedImageSpecialistUnsupported)
        XCTAssertEqual(mockSettings.selectedVisionModelId, "unsupported")
        XCTAssertEqual(mockSettings.selectedImageGenerationModelId, "unsupported")
    }

    func test_refreshAsync_dualModelLosesTransport_keepsBothSelectionsUnavailable() async throws {
        // Given
        sut.send(.visionModelSelected("dual"))
        sut.send(.imageGenerationModelSelected("dual"))
        mockFetchModels.result = .success([
            LLMModel(id: "dual", capabilities: [.vision, .imageGeneration], mode: .audioSpeech)
        ])

        // When
        await sut.refreshAsync()

        // Then
        let state = try XCTUnwrap(loadedState)
        XCTAssertTrue(state.visionModels.isEmpty)
        XCTAssertTrue(state.imageGenerationModels.isEmpty)
        XCTAssertTrue(state.isSelectedVisionModelUnavailable)
        XCTAssertTrue(state.isSelectedImageModelUnavailable)
        XCTAssertEqual(state.selectedVisionModelId, "dual")
        XCTAssertEqual(state.selectedImageGenerationModelId, "dual")
        XCTAssertEqual(mockSettings.selectedVisionModelId, "dual")
        XCTAssertEqual(mockSettings.selectedImageGenerationModelId, "dual")
    }

    func test_refreshAsync_selectedModelsDisappear_keepsIdsWithoutFallback() async throws {
        // Given
        sut.send(.visionModelSelected("vision"))
        sut.send(.imageGenerationModelSelected("images"))
        mockFetchModels.result = .success([models[3]])

        // When
        await sut.refreshAsync()

        // Then
        let state = try XCTUnwrap(loadedState)
        XCTAssertEqual(state.selectedVisionModelId, "vision")
        XCTAssertEqual(state.selectedImageGenerationModelId, "images")
        XCTAssertTrue(state.isSelectedVisionModelUnavailable)
        XCTAssertTrue(state.isSelectedImageModelUnavailable)
        XCTAssertEqual(mockSettings.selectedVisionModelId, "vision")
        XCTAssertEqual(mockSettings.selectedImageGenerationModelId, "images")
    }

    func test_refreshAsync_capabilitiesRemoved_keepsIdsUnavailable() async throws {
        // Given
        sut.send(.visionModelSelected("vision"))
        sut.send(.imageGenerationModelSelected("images"))
        mockFetchModels.result = .success([LLMModel(id: "vision"), LLMModel(id: "images")])

        // When
        await sut.refreshAsync()

        // Then
        let state = try XCTUnwrap(loadedState)
        XCTAssertTrue(state.isSelectedVisionModelUnavailable)
        XCTAssertTrue(state.isSelectedImageModelUnavailable)
        XCTAssertEqual(state.selectedVisionModelId, "vision")
        XCTAssertEqual(state.selectedImageGenerationModelId, "images")
        XCTAssertEqual(mockSettings.selectedVisionModelId, "vision")
        XCTAssertEqual(mockSettings.selectedImageGenerationModelId, "images")
    }

    func test_refreshAsync_selectedModelsReappear_restoresAvailability() async throws {
        // Given
        sut.send(.visionModelSelected("vision"))
        sut.send(.imageGenerationModelSelected("images"))
        mockFetchModels.result = .success([])
        await sut.refreshAsync()
        mockFetchModels.result = .success(models)

        // When
        await sut.refreshAsync()

        // Then
        let state = try XCTUnwrap(loadedState)
        XCTAssertEqual(state.selectedVisionModelId, "vision")
        XCTAssertEqual(state.selectedImageGenerationModelId, "images")
        XCTAssertFalse(state.isSelectedVisionModelUnavailable)
        XCTAssertFalse(state.isSelectedImageModelUnavailable)
    }

    func test_refreshAsync_noneAfterModelsDisappear_doesNotReselectReturningModels() async throws {
        // Given
        sut.send(.visionModelSelected("vision"))
        sut.send(.imageGenerationModelSelected("images"))
        mockFetchModels.result = .success([])
        await sut.refreshAsync()
        sut.send(.visionModelSelected(nil))
        sut.send(.imageGenerationModelSelected(nil))
        mockFetchModels.result = .success(models)

        // When
        await sut.refreshAsync()

        // Then
        let state = try XCTUnwrap(loadedState)
        XCTAssertNil(state.selectedVisionModelId)
        XCTAssertNil(state.selectedImageGenerationModelId)
        XCTAssertNil(mockSettings.selectedVisionModelId)
        XCTAssertNil(mockSettings.selectedImageGenerationModelId)
        XCTAssertFalse(state.isSelectedVisionModelUnavailable)
        XCTAssertFalse(state.isSelectedImageModelUnavailable)
    }

}

// MARK: - Private

private extension ModelsViewModelImageAndVisionTests {
    func loadOnAppearance() async {
        sut.send(.viewAppeared)
        let didLoad = expectation(description: "Models state updated after loading")
        withObservationTracking {
            _ = sut.state
        } onChange: {
            didLoad.fulfill()
        }
        await fulfillment(of: [didLoad], timeout: 1)
    }
}
