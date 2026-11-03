//
//  FetchModelsUseCaseOverrideTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 03/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class FetchModelsUseCaseOverrideTests: XCTestCase {
    func test_execute_manualCapabilities_replaceEnrichmentAndPreserveMetadata() async throws {
        let repository = MockModelsRepository()
        let settings = MockSettingsManager()
        settings.serverBaseURL = "https://example.com/v1"
        repository.fetchModelsResult = .success([LLMModel(id: "model")])
        repository.fetchModelInfoResult = .success([
            LLMModel(id: "model", capabilities: [.functionCalling], maxInputTokens: 8192, inputCostPerToken: 0.01)
        ])
        settings.setModelCapabilityOverride(
            [.vision, .imageGeneration], for: "model", serverBaseURL: settings.serverBaseURL
        )
        let sut = FetchModelsUseCase(repository: repository, settingsManager: settings)

        let models = try await sut.execute()
        let model = try XCTUnwrap(models.first)

        XCTAssertEqual(model.capabilities, [.vision, .imageGeneration])
        XCTAssertEqual(model.detectedCapabilities, [.functionCalling])
        XCTAssertEqual(model.mode, .chat)
        XCTAssertEqual(model.maxInputTokens, 8192)
        XCTAssertEqual(model.inputCostPerToken, 0.01)
        XCTAssertTrue(model.isVisionSpecialist)
        XCTAssertTrue(model.isImageGenerationSpecialist)
    }

    func test_execute_emptyOverrideAndReset_useLatestDetectedCapabilities() async throws {
        let repository = MockModelsRepository()
        let settings = MockSettingsManager()
        repository.fetchModelsResult = .success([LLMModel(id: "model")])
        repository.fetchModelInfoResult = .success([LLMModel(id: "model", capabilities: [.vision])])
        settings.setModelCapabilityOverride([], for: "model", serverBaseURL: settings.serverBaseURL)
        let sut = FetchModelsUseCase(repository: repository, settingsManager: settings)

        let firstLoad = try await sut.execute()
        repository.fetchModelInfoResult = .success([LLMModel(id: "model", capabilities: [.vision, .functionCalling])])
        let refreshed = try await sut.execute()
        settings.setModelCapabilityOverride(nil, for: "model", serverBaseURL: settings.serverBaseURL)
        let automatic = try await sut.execute()

        XCTAssertEqual(firstLoad.first?.capabilities, [])
        XCTAssertEqual(refreshed.first?.capabilities, [])
        XCTAssertEqual(refreshed.first?.detectedCapabilities, [.vision, .functionCalling])
        XCTAssertEqual(automatic.first?.capabilities, [.vision, .functionCalling])
        XCTAssertNil(automatic.first?.capabilityOverride)
    }

    func test_execute_missingEnrichment_appliesOverrideOnlyForCurrentServer() async throws {
        let repository = MockModelsRepository()
        let settings = MockSettingsManager()
        settings.serverBaseURL = "https://first.example/v1"
        repository.fetchModelsResult = .success([LLMModel(id: "model")])
        repository.fetchModelInfoResult = .failure(APIError.serverUnreachable)
        settings.setModelCapabilityOverride([.vision], for: "model", serverBaseURL: settings.serverBaseURL)
        let sut = FetchModelsUseCase(repository: repository, settingsManager: settings)

        let firstServer = try await sut.execute()
        settings.serverBaseURL = "https://second.example/v1"
        let secondServer = try await sut.execute()

        XCTAssertEqual(firstServer.first?.capabilities, [.vision])
        XCTAssertEqual(secondServer.first?.capabilities, [])
        XCTAssertNil(secondServer.first?.capabilityOverride)
    }

    func test_execute_ollamaEnrichment_manualCapabilitiesTakePrecedence() async throws {
        let repository = MockModelsRepository()
        let settings = MockSettingsManager()
        repository.fetchModelsResult = .success([LLMModel(id: "model")])
        repository.fetchModelInfoResult = .success([])
        repository.fetchOllamaModelDetailsResult = OllamaShowResponse(capabilities: ["vision", "tools"], details: nil)
        settings.setModelCapabilityOverride([.vision], for: "model", serverBaseURL: settings.serverBaseURL)

        let models = try await FetchModelsUseCase(repository: repository, settingsManager: settings).execute()

        XCTAssertEqual(models.first?.capabilities, [.vision])
        XCTAssertEqual(models.first?.detectedCapabilities, [.vision, .functionCalling])
        XCTAssertEqual(models.first?.providerName, "Ollama")
    }
}
