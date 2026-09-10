//
//  ModelsRepository.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

protocol ModelsRepositoryProtocol: Sendable {
    func fetchModels() async throws -> [LLMModel]
    func fetchModelInfo() async throws -> [LLMModel]
    func fetchOllamaModelDetails(for modelId: String, rootURL: String) async -> OllamaShowResponse?
}

struct ModelsRepository: ModelsRepositoryProtocol {
    // MARK: - Properties

    private let apiClient: APIClientProtocol

    // MARK: - Init

    init(apiClient: APIClientProtocol = APIClient()) {
        self.apiClient = apiClient
    }

    // MARK: - Public

    func fetchModels() async throws -> [LLMModel] {
        LogManager.info("fetchModels")
        let response: ModelsResponse = try await apiClient.request(
            endpoint: "models",
            method: .get,
            body: nil
        )

        let models = response.data
            .map { LLMModel(id: $0.id, ownedBy: $0.ownedBy ?? "") }
            .sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
        LogManager.success("fetchModels returned \(models.count) models")
        return models
    }

    func fetchModelInfo() async throws -> [LLMModel] {
        LogManager.info("fetchModelInfo")
        let response: ModelInfoResponse = try await apiClient.request(
            endpoint: "model/info",
            method: .get,
            body: nil
        )

        var result = response.data.map { info -> LLMModel in
            let inferredProvider = Self.inferLitellmProvider(
                from: info.modelInfo?.litellmProvider,
                modelParam: info.litellmParams?.model
            )
            let supportsStructuredToolCalling = Self.supportsStructuredToolCalling(
                explicitProvider: info.modelInfo?.litellmProvider,
                modelParam: info.litellmParams?.model
            )
            if info.modelInfo?.supportsFunctionCalling == true, !supportsStructuredToolCalling {
                LogManager.warning(
                    "Model \(info.modelName) uses LiteLLM ollama/ JSON tool emulation; " +
                        "configure ollama_chat/ to enable native tool calling"
                )
            }
            return LLMModel(
                id: info.modelName,
                capabilities: Self.capabilitiesFromModelInfo(
                    info.modelInfo,
                    includeFunctionCalling: supportsStructuredToolCalling
                ),
                provider: LLMModel.Provider.from(inferredProvider),
                mode: LLMModel.Mode(rawString: info.modelInfo?.mode),
                providerName: LLMModel.Provider.displayName(from: inferredProvider),
                maxInputTokens: info.modelInfo?.maxInputTokens,
                maxOutputTokens: info.modelInfo?.maxOutputTokens,
                inputCostPerToken: info.modelInfo?.inputCostPerToken,
                outputCostPerToken: info.modelInfo?.outputCostPerToken
            )
        }

        let ollamaItems = Self.ollamaSupplementItems(from: response)
        if !ollamaItems.isEmpty {
            result = await supplementOllamaCapabilities(in: result, using: ollamaItems)
        }

        LogManager.success("fetchModelInfo returned \(result.count) models")
        return result
    }

    func fetchOllamaModelDetails(for modelId: String, rootURL: String) async -> OllamaShowResponse? {
        guard let url = URL(string: rootURL)?.appendingPathComponent("api/show") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5

        guard let body = try? JSONEncoder().encode(OllamaShowRequest(model: modelId)) else { return nil }
        request.httpBody = body

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else { return nil }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(OllamaShowResponse.self, from: data)
    }

    nonisolated static func supportsStructuredToolCalling(
        explicitProvider: String?,
        modelParam: String?
    ) -> Bool {
        let normalizedModel = modelParam?.lowercased() ?? ""
        if normalizedModel.hasPrefix("ollama_chat/") { return true }
        if normalizedModel.hasPrefix("ollama/") { return false }
        return explicitProvider?.lowercased() != "ollama"
    }
}

// MARK: - Private

private struct OllamaSupplementItem {
    let llmModelId: String
    let nativeModelId: String
    let apiBase: String
    let supportsStructuredToolCalling: Bool
}

private extension ModelsRepository {
    nonisolated static func capabilitiesFromModelInfo(
        _ modelInfo: ModelInfoResponse.ModelInfo?,
        includeFunctionCalling: Bool
    ) -> [LLMModel.Capability] {
        var caps: [LLMModel.Capability] = []
        if modelInfo?.supportsVision == true { caps.append(.vision) }
        if includeFunctionCalling, modelInfo?.supportsFunctionCalling == true { caps.append(.functionCalling) }
        if includeFunctionCalling, modelInfo?.supportsParallelFunctionCalling == true {
            caps.append(.parallelFunctionCalling)
        }
        if modelInfo?.supportsResponseSchema == true { caps.append(.jsonSchema) }
        if modelInfo?.supportsWebSearch == true { caps.append(.webSearch) }
        if modelInfo?.mode == LLMModel.Mode.imageGeneration.rawValue ||
            modelInfo?.supportedOutputModalities?.contains("image") == true {
            caps.append(.imageGeneration)
        }
        return caps
    }

    nonisolated static func ollamaSupplementItems(from response: ModelInfoResponse) -> [OllamaSupplementItem] {
        response.data.compactMap { info in
            let provider = info.modelInfo?.litellmProvider?.lowercased()
            let rawModelParam = info.litellmParams?.model ?? ""
            let isOllamaByProvider = provider == "ollama" || provider == "ollama_chat"
            let isOllamaByParams = rawModelParam.hasPrefix("ollama/") || rawModelParam.hasPrefix("ollama_chat/")
            guard isOllamaByProvider || isOllamaByParams else { return nil }
            let apiBase = info.litellmParams?.apiBase ?? "http://localhost:11434"
            let rawModel = rawModelParam.isEmpty ? info.modelName : rawModelParam
            let nativeId = rawModel
                .replacingOccurrences(of: "ollama_chat/", with: "")
                .replacingOccurrences(of: "ollama/", with: "")
            return OllamaSupplementItem(
                llmModelId: info.modelName,
                nativeModelId: nativeId,
                apiBase: apiBase,
                supportsStructuredToolCalling: supportsStructuredToolCalling(
                    explicitProvider: info.modelInfo?.litellmProvider,
                    modelParam: info.litellmParams?.model
                )
            )
        }
    }

    func supplementOllamaCapabilities(
        in result: [LLMModel],
        using items: [OllamaSupplementItem]
    ) async -> [LLMModel] {
        var supplementalCaps: [String: [LLMModel.Capability]] = [:]
        await withTaskGroup(of: (String, [LLMModel.Capability]).self) { group in
            for item in items {
                group.addTask {
                    guard let detail = await self.fetchOllamaModelDetails(
                        for: item.nativeModelId,
                        rootURL: item.apiBase
                    ) else { return (item.llmModelId, []) }
                    let capabilities = Self.ollamaCapabilitiesFromNative(detail.capabilities ?? [])
                    let filtered = item.supportsStructuredToolCalling
                        ? capabilities
                        : capabilities.filter { $0 != .functionCalling }
                    return (item.llmModelId, filtered)
                }
            }
            for await (id, caps) in group where !caps.isEmpty {
                supplementalCaps[id] = caps
            }
        }
        return result.map { model in
            guard let extra = supplementalCaps[model.id] else { return model }
            var updated = model
            let existing = Set(updated.capabilities.map(\.rawValue))
            updated.capabilities += extra.filter { !existing.contains($0.rawValue) }
            return updated
        }
    }

    /// Maps Ollama native capability strings to `LLMModel.Capability` values.
    nonisolated static func ollamaCapabilitiesFromNative(_ capabilities: [String]) -> [LLMModel.Capability] {
        var result: [LLMModel.Capability] = []
        if capabilities.contains("vision") { result.append(.vision) }
        if capabilities.contains("tools") { result.append(.functionCalling) }
        if capabilities.contains("thinking") { result.append(.thinking) }
        if capabilities.contains("audio") { result.append(.audioInput) }
        if capabilities.contains("image") { result.append(.imageGeneration) }
        return result
    }

    /// Returns the effective LiteLLM provider string, falling back to the
    /// `litellm_params.model` prefix when `model_info.litellm_provider` is absent.
    nonisolated static func inferLitellmProvider(from explicit: String?, modelParam: String?) -> String? {
        if let explicit, !explicit.isEmpty { return explicit }
        guard let param = modelParam else { return nil }
        if param.hasPrefix("ollama_chat/") { return "ollama_chat" }
        if param.hasPrefix("ollama/") { return "ollama" }
        if param.hasPrefix("hosted_vllm/") { return "hosted_vllm" }
        if param.hasPrefix("vllm/") { return "vllm" }
        if param.hasPrefix("openai/") { return "openai" }
        if param.hasPrefix("anthropic/") { return "anthropic" }
        if param.hasPrefix("gemini/") { return "gemini" }
        if param.hasPrefix("deepseek/") { return "deepseek" }
        return nil
    }
}
