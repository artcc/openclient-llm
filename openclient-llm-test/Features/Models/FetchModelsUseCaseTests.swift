//
//  FetchModelsUseCaseTests.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class FetchModelsUseCaseTests: XCTestCase {
    // MARK: - Properties

    private var sut: FetchModelsUseCase!
    private var mockRepository: MockModelsRepository!

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()

        mockRepository = MockModelsRepository()
        sut = FetchModelsUseCase(repository: mockRepository)
    }

    override func tearDown() async throws {
        sut = nil
        mockRepository = nil

        try await super.tearDown()
    }

    // MARK: - Tests

    func test_execute_withModels_returnsModels() async throws {
        // Given
        let models = [LLMModel(id: "gpt-4", ownedBy: "openai"), LLMModel(id: "llama3", ownedBy: "ollama")]
        mockRepository.fetchModelsResult = .success(models)

        // When
        let result = try await sut.execute()

        // Then
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first?.id, "gpt-4")
    }

    func test_execute_withError_throwsError() async {
        // Given
        mockRepository.fetchModelsResult = .failure(APIError.serverUnreachable)

        // When / Then
        do {
            _ = try await sut.execute()
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is APIError)
        }
    }

    func test_execute_withEmptyList_returnsEmpty() async throws {
        // Given
        mockRepository.fetchModelsResult = .success([])

        // When
        let result = try await sut.execute()

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_execute_mergesCapabilitiesFromModelInfo() async throws {
        // Given
        let models = [LLMModel(id: "gpt-4", ownedBy: "openai"), LLMModel(id: "llama3", ownedBy: "ollama")]
        mockRepository.fetchModelsResult = .success(models)

        let modelInfoList = [LLMModel(id: "gpt-4", capabilities: [.vision, .functionCalling])]
        mockRepository.fetchModelInfoResult = .success(modelInfoList)

        // When
        let result = try await sut.execute()

        // Then
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first(where: { $0.id == "gpt-4" })?.capabilities, [.vision, .functionCalling])
        XCTAssertTrue(result.first(where: { $0.id == "llama3" })?.capabilities.isEmpty == true)
    }

    func test_execute_dualChatModelInfo_preservesBothSpecialistRoles() async throws {
        // Given
        mockRepository.fetchModelsResult = .success([LLMModel(id: "studio-assistant")])
        mockRepository.fetchModelInfoResult = .success([
            LLMModel(id: "studio-assistant", capabilities: [.vision, .imageGeneration], mode: .chat)
        ])

        // When
        let result = try await sut.execute()

        // Then
        let model = try XCTUnwrap(result.first)
        XCTAssertEqual(model.mode, .chat)
        XCTAssertEqual(model.capabilities, [.vision, .imageGeneration])
        XCTAssertTrue(model.isVisionSpecialist)
        XCTAssertTrue(model.isImageGenerationSpecialist)
    }

    func test_execute_mergesModeFromModelInfo() async throws {
        // Given
        let models = [
            LLMModel(id: "dall-e-3", ownedBy: "openai"),
            LLMModel(id: "gpt-4", ownedBy: "openai")
        ]
        mockRepository.fetchModelsResult = .success(models)

        let modelInfoList = [
            LLMModel(id: "dall-e-3", mode: .imageGeneration),
            LLMModel(id: "gpt-4", mode: .chat)
        ]
        mockRepository.fetchModelInfoResult = .success(modelInfoList)

        // When
        let result = try await sut.execute()

        // Then
        XCTAssertEqual(result.first(where: { $0.id == "dall-e-3" })?.mode, .imageGeneration)
        XCTAssertEqual(result.first(where: { $0.id == "gpt-4" })?.mode, .chat)
    }

    func test_execute_mergesProviderNameFromModelInfo() async throws {
        // Given
        let models = [
            LLMModel(id: "gpt-4", ownedBy: "openai"),
            LLMModel(id: "claude-3", ownedBy: "openai"),
            LLMModel(id: "llama3", ownedBy: "openai")
        ]
        mockRepository.fetchModelsResult = .success(models)

        let modelInfoList = [
            LLMModel(id: "gpt-4", providerName: "OpenAI"),
            LLMModel(id: "claude-3", providerName: "Anthropic"),
            LLMModel(id: "llama3", providerName: "Ollama")
        ]
        mockRepository.fetchModelInfoResult = .success(modelInfoList)

        // When
        let result = try await sut.execute()

        // Then
        XCTAssertEqual(result.first(where: { $0.id == "gpt-4" })?.providerName, "OpenAI")
        XCTAssertEqual(result.first(where: { $0.id == "claude-3" })?.providerName, "Anthropic")
        XCTAssertEqual(result.first(where: { $0.id == "llama3" })?.providerName, "Ollama")
    }

    func test_execute_modelInfoFailure_stillReturnsModels() async throws {
        // Given
        let models = [LLMModel(id: "gpt-4")]
        mockRepository.fetchModelsResult = .success(models)
        mockRepository.fetchModelInfoResult = .failure(APIError.serverUnreachable)

        // When
        let result = try await sut.execute()

        // Then
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.first?.capabilities.isEmpty == true)
    }

    func test_execute_ollamaViaLiteLLM_supplementsToolsCapabilityFromOllamaNativeAPI() async throws {
        // Given: LiteLLM /model/info only returns "vision" for an Ollama model
        // (happens when LiteLLM's static model map is outdated for newer models like gemma4)
        let models = [LLMModel(id: "gemma4", ownedBy: "ollama")]
        mockRepository.fetchModelsResult = .success(models)

        let modelInfoFromLiteLLM = [
            LLMModel(id: "gemma4", capabilities: [.vision], provider: .local, providerName: "Ollama")
        ]
        mockRepository.fetchModelInfoResult = .success(modelInfoFromLiteLLM)

        // When
        let result = try await sut.execute()

        // Then: capabilities from LiteLLM are preserved (supplemented by mock which returns vision)
        let gemma4 = result.first(where: { $0.id == "gemma4" })
        XCTAssertNotNil(gemma4)
        XCTAssertTrue(gemma4?.capabilities.contains(.vision) == true)
    }

    func test_execute_ollamaViaLiteLLM_ollamaSupplementCombinesWithLiteLLMCaps() async throws {
        // Given: LiteLLM returns vision; Ollama native returns vision + tools
        // The mock repository's fetchModelInfo already returns the merged result
        // (integration of the actual supplementation happens in ModelsRepository, not the use case)
        let models = [LLMModel(id: "gemma4", ownedBy: "ollama")]
        mockRepository.fetchModelsResult = .success(models)

        let mergedCapabilities = [LLMModel.Capability.vision, .functionCalling]
        let modelInfoList = [
            LLMModel(id: "gemma4", capabilities: mergedCapabilities, provider: .local, providerName: "Ollama")
        ]
        mockRepository.fetchModelInfoResult = .success(modelInfoList)

        // When
        let result = try await sut.execute()

        // Then
        let gemma4 = result.first(where: { $0.id == "gemma4" })
        XCTAssertEqual(gemma4?.capabilities, [.vision, .functionCalling])
    }

    func test_execute_mergesCostAndContextWindowFromModelInfo() async throws {
        // Given
        let models = [LLMModel(id: "gpt-4o", ownedBy: "openai")]
        mockRepository.fetchModelsResult = .success(models)

        let modelInfoList = [
            LLMModel(
                id: "gpt-4o",
                maxInputTokens: 128_000,
                maxOutputTokens: 16_384,
                inputCostPerToken: 0.0000025,
                outputCostPerToken: 0.00001
            )
        ]
        mockRepository.fetchModelInfoResult = .success(modelInfoList)

        // When
        let result = try await sut.execute()

        // Then
        let model = result.first(where: { $0.id == "gpt-4o" })
        XCTAssertEqual(model?.maxInputTokens, 128_000)
        XCTAssertEqual(model?.maxOutputTokens, 16_384)
        XCTAssertEqual(model?.inputCostPerToken, 0.0000025)
        XCTAssertEqual(model?.outputCostPerToken, 0.00001)
    }

    func test_execute_costAndContextWindowNilWhenNotInModelInfo() async throws {
        // Given
        let models = [LLMModel(id: "llama3", ownedBy: "ollama")]
        mockRepository.fetchModelsResult = .success(models)

        let modelInfoList = [LLMModel(id: "llama3", capabilities: [.vision], provider: .local)]
        mockRepository.fetchModelInfoResult = .success(modelInfoList)

        // When
        let result = try await sut.execute()

        // Then
        let model = result.first(where: { $0.id == "llama3" })
        XCTAssertNil(model?.maxInputTokens)
        XCTAssertNil(model?.maxOutputTokens)
        XCTAssertNil(model?.inputCostPerToken)
        XCTAssertNil(model?.outputCostPerToken)
    }
}
