//
//  ModelInfoResponse.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

nonisolated struct ModelInfoResponse: Decodable, Sendable {
    let data: [ModelInfoData]

    struct ModelInfoData: Decodable, Sendable {
        let modelName: String
        let litellmParams: LiteLLMParams?
        let modelInfo: ModelInfo?
    }

    struct LiteLLMParams: Decodable, Sendable {
        /// Underlying model identifier, e.g. "ollama/gemma4:27b"
        let model: String?
        /// Base URL of the backend provider, e.g. "http://localhost:11434"
        let apiBase: String?
    }

    struct ModelInfo: Decodable, Sendable {
        let maxTokens: Int?
        let maxInputTokens: Int?
        let maxOutputTokens: Int?
        let inputCostPerToken: Double?
        let outputCostPerToken: Double?
        let supportsVision: Bool?
        let supportsFunctionCalling: Bool?
        let supportsParallelFunctionCalling: Bool?
        let supportsResponseSchema: Bool?
        let supportsWebSearch: Bool?
        let supportedOutputModalities: [String]?
        let mode: String?
        let litellmProvider: String?
    }
}
