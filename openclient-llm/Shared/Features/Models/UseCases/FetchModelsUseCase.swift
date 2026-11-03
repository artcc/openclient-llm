//
//  FetchModelsUseCase.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

protocol FetchModelsUseCaseProtocol: Sendable {
    func execute() async throws -> [LLMModel]
}

struct FetchModelsUseCase: FetchModelsUseCaseProtocol {
    // MARK: - Properties

    private let repository: ModelsRepositoryProtocol
    private let settingsManager: SettingsManagerProtocol

    // MARK: - Init

    init(
        repository: ModelsRepositoryProtocol = ModelsRepository(),
        settingsManager: SettingsManagerProtocol = SettingsManager()
    ) {
        self.repository = repository
        self.settingsManager = settingsManager
    }

    // MARK: - Execute

    func execute() async throws -> [LLMModel] {
        let serverBaseURL = settingsManager.getServerBaseURL()
        var models = try await repository.fetchModels()

        if let modelInfoList = try? await repository.fetchModelInfo(), !modelInfoList.isEmpty {
            let infoByName = Dictionary(
                modelInfoList.map { ($0.id, $0) },
                uniquingKeysWith: { _, last in last }
            )

            models = models.map { model in
                var updated = model
                if let info = infoByName[model.id] {
                    updated.detectedCapabilities = info.capabilities
                    updated.provider = info.provider
                    updated.mode = info.mode
                    updated.providerName = info.providerName
                    updated.maxInputTokens = info.maxInputTokens
                    updated.maxOutputTokens = info.maxOutputTokens
                    updated.inputCostPerToken = info.inputCostPerToken
                    updated.outputCostPerToken = info.outputCostPerToken
                } else {
                    updated.provider = LLMModel.Provider.from(model.ownedBy)
                }
                return updated
            }
        } else {
            // LiteLLM /model/info not available — try Ollama /api/show enrichment
            let rootURL = ollamaRootURL(from: serverBaseURL)
            let ollamaDetails = await fetchOllamaDetails(for: models, rootURL: rootURL)

            models = models.map { model in
                var updated = model
                if let detail = ollamaDetails[model.id] {
                    updated.detectedCapabilities = mapOllamaCapabilities(detail.capabilities ?? [])
                    updated.provider = .local
                    updated.providerName = "Ollama"
                    updated.mode = mapOllamaMode(detail.capabilities ?? [])
                } else {
                    updated.provider = LLMModel.Provider.from(model.ownedBy)
                }
                return updated
            }
        }

        return models.map { model in
            var updated = model
            updated.capabilityOverride = settingsManager.getModelCapabilityOverride(
                for: model.id, serverBaseURL: serverBaseURL
            )
            return updated
        }
    }
}

// MARK: - Private

private extension FetchModelsUseCase {
    func fetchOllamaDetails(for models: [LLMModel], rootURL: String) async -> [String: OllamaShowResponse] {
        await withTaskGroup(of: (String, OllamaShowResponse?).self) { group in
            for model in models {
                group.addTask {
                    let detail = await repository.fetchOllamaModelDetails(for: model.id, rootURL: rootURL)
                    return (model.id, detail)
                }
            }
            var results: [String: OllamaShowResponse] = [:]
            for await (id, response) in group {
                if let response {
                    results[id] = response
                }
            }
            return results
        }
    }

    func mapOllamaCapabilities(_ capabilities: [String]) -> [LLMModel.Capability] {
        var result: [LLMModel.Capability] = []
        if capabilities.contains("vision") { result.append(.vision) }
        if capabilities.contains("tools") { result.append(.functionCalling) }
        if capabilities.contains("thinking") { result.append(.thinking) }
        if capabilities.contains("audio") { result.append(.audioInput) }
        if capabilities.contains("image") { result.append(.imageGeneration) }
        return result
    }

    func mapOllamaMode(_ capabilities: [String]) -> LLMModel.Mode {
        if capabilities.contains("embed") { return .embedding }
        return .chat
    }

    /// Strips the OpenAI-compatible `/v1` suffix from the base URL so we can
    /// reach Ollama's native endpoints (e.g. `/api/show`) at the server root.
    func ollamaRootURL(from baseURL: String) -> String {
        var url = baseURL.trimmingCharacters(in: .whitespaces)
        if url.hasSuffix("/") { url = String(url.dropLast()) }
        if url.lowercased().hasSuffix("/v1") { url = String(url.dropLast(3)) }
        return url
    }
}
