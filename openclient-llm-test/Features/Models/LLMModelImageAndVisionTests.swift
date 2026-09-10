//
//  LLMModelImageAndVisionTests.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class LLMModelImageAndVisionTests: XCTestCase {
    func test_supportsNativeVision_withoutVisionCapability_doesNotInferFromIdOrMode() {
        // Given
        let model = LLMModel(id: "vision-image-model", capabilities: [.imageGeneration], mode: .imageGeneration)

        // When
        let supportsVision = model.supportsNativeVision

        // Then
        XCTAssertFalse(supportsVision)
        XCTAssertFalse(model.isVisionSpecialist)
    }

    func test_isVisionSpecialist_visionCapability_requiresSupportedMode() {
        // Given
        let cases: [(LLMModel.Mode, Bool)] = [
            (.chat, true), (.completion, true), (.unknown, true),
            (.imageGeneration, false), (.embedding, false), (.audioSpeech, false), (.audioTranscription, false)
        ]

        for (mode, expected) in cases {
            let model = LLMModel(id: "vision", capabilities: [.vision], mode: mode)

            // When
            let isSpecialist = model.isVisionSpecialist

            // Then
            XCTAssertTrue(model.supportsNativeVision, mode.rawValue)
            XCTAssertEqual(isSpecialist, expected, mode.rawValue)
        }
    }

    func test_isVisionSpecialist_supportedModesWithoutVision_returnsFalse() {
        // Given
        let modes: [LLMModel.Mode] = [.chat, .completion, .unknown]

        for mode in modes {
            let model = LLMModel(id: "text", mode: mode)

            // When
            let isSpecialist = model.isVisionSpecialist

            // Then
            XCTAssertFalse(isSpecialist, mode.rawValue)
        }
    }

    func test_supportsNativeImageGeneration_imageModeWithoutCapability_returnsTrue() {
        // Given
        let model = LLMModel(id: "images", mode: .imageGeneration)

        // When
        let supportsImages = model.supportsNativeImageGeneration

        // Then
        XCTAssertTrue(supportsImages)
        XCTAssertTrue(model.isImageGenerationSpecialist)
    }

    func test_isImageGenerationSpecialist_imageCapability_requiresSupportedTransport() {
        // Given
        let cases: [(LLMModel.Mode, Bool)] = [
            (.chat, true), (.completion, true), (.unknown, true), (.imageGeneration, true),
            (.embedding, false), (.audioSpeech, false), (.audioTranscription, false)
        ]

        for (mode, expected) in cases {
            let model = LLMModel(id: "images", capabilities: [.imageGeneration], mode: mode)

            // When
            let isSpecialist = model.isImageGenerationSpecialist

            // Then
            XCTAssertTrue(model.supportsNativeImageGeneration, mode.rawValue)
            XCTAssertEqual(isSpecialist, expected, mode.rawValue)
        }
    }

    func test_supportsNativeImageGeneration_noMetadata_doesNotInferFromId() {
        // Given
        let model = LLMModel(id: "image-generation-model")

        // When
        let supportsImages = model.supportsNativeImageGeneration

        // Then
        XCTAssertFalse(supportsImages)
        XCTAssertFalse(model.isImageGenerationSpecialist)
    }

    func test_imageSupport_dualCapabilityChat_exposesNonisolatedContracts() {
        // Given
        let model = LLMModel(id: "multimodal", capabilities: [.vision, .imageGeneration])

        // When
        let flags = Self.supportFlags(for: model)

        // Then
        XCTAssertEqual(flags, [true, true, true, true])
    }

    // MARK: - Private

    private nonisolated static func supportFlags(for model: LLMModel) -> [Bool] {
        [
            model.supportsNativeVision,
            model.supportsNativeImageGeneration,
            model.isVisionSpecialist,
            model.isImageGenerationSpecialist
        ]
    }
}
