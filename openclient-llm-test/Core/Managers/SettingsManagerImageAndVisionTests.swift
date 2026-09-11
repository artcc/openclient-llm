//
//  SettingsManagerImageAndVisionTests.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class SettingsManagerImageAndVisionTests: XCTestCase {
    // MARK: - Properties

    private var sut: SettingsManager!
    private var defaults: UserDefaults!
    private let suiteName = "com.artcc.openclient-llm.test.image-vision.\(UUID().uuidString)"

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()

        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        sut = SettingsManager(defaults: defaults, keychainManager: MockKeychainManager())
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        sut = nil
        defaults = nil

        try await super.tearDown()
    }

    // MARK: - Tests

    func test_getSelectedModels_noSavedSelections_returnsNilForBothRoles() {
        // Given
        sut.setSelectedModelId("chat")
        sut.setSelectedTTSModelId("speech")
        sut.setSelectedSTTModelId("transcription")

        // When
        let visionId = sut.getSelectedVisionModelId()
        let imageId = sut.getSelectedImageGenerationModelId()

        // Then
        XCTAssertNil(visionId)
        XCTAssertNil(imageId)
    }

    func test_setSelectedModels_independentIds_persistsAcrossManagerInstances() {
        // Given
        sut.setSelectedVisionModelId("vision")
        sut.setSelectedImageGenerationModelId("images")

        // When
        let restored = SettingsManager(defaults: defaults, keychainManager: MockKeychainManager())

        // Then
        XCTAssertEqual(restored.getSelectedVisionModelId(), "vision")
        XCTAssertEqual(restored.getSelectedImageGenerationModelId(), "images")
    }

    func test_setSelectedVisionModelId_nil_clearsOnlyVision() {
        // Given
        sut.setSelectedModelId("chat")
        sut.setSelectedVisionModelId("vision")
        sut.setSelectedImageGenerationModelId("images")

        // When
        sut.setSelectedVisionModelId(nil)

        // Then
        XCTAssertNil(sut.getSelectedVisionModelId())
        XCTAssertEqual(sut.getSelectedImageGenerationModelId(), "images")
        XCTAssertEqual(sut.getSelectedModelId(), "chat")
    }

    func test_setSelectedImageGenerationModelId_nil_clearsOnlyImageGeneration() {
        // Given
        sut.setSelectedModelId("chat")
        sut.setSelectedVisionModelId("vision")
        sut.setSelectedImageGenerationModelId("images")

        // When
        sut.setSelectedImageGenerationModelId(nil)

        // Then
        XCTAssertNil(sut.getSelectedImageGenerationModelId())
        XCTAssertEqual(sut.getSelectedVisionModelId(), "vision")
        XCTAssertEqual(sut.getSelectedModelId(), "chat")
    }

    func test_setSelectedModels_sameId_keepsBothRolesIndependent() {
        // Given
        sut.setSelectedVisionModelId("multimodal")
        sut.setSelectedImageGenerationModelId("multimodal")

        // When
        sut.setSelectedVisionModelId("other-vision")

        // Then
        XCTAssertEqual(sut.getSelectedVisionModelId(), "other-vision")
        XCTAssertEqual(sut.getSelectedImageGenerationModelId(), "multimodal")
    }

    func test_deleteAll_savedImageAndVisionSelections_removesBothPersistedIds() {
        // Given
        sut.setSelectedVisionModelId("vision")
        sut.setSelectedImageGenerationModelId("images")

        // When
        sut.deleteAll()
        let restored = SettingsManager(defaults: defaults, keychainManager: MockKeychainManager())

        // Then
        XCTAssertNil(restored.getSelectedVisionModelId())
        XCTAssertNil(restored.getSelectedImageGenerationModelId())
    }

    func test_mockSettingsManager_deleteAll_removesBothSelections() {
        // Given
        let mock = MockSettingsManager()
        mock.setSelectedVisionModelId("vision")
        mock.setSelectedImageGenerationModelId("images")

        // When
        mock.deleteAll()

        // Then
        XCTAssertNil(mock.getSelectedVisionModelId())
        XCTAssertNil(mock.getSelectedImageGenerationModelId())
    }
}
