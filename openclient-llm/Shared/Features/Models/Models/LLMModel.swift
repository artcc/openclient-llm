//
//  LLMModel.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

struct LLMModel: Identifiable, Equatable, Sendable {
    // MARK: - Properties

    let id: String
    let ownedBy: String
    var capabilities: [Capability]
    var provider: Provider
    var mode: Mode
    var providerName: String
    var maxInputTokens: Int?
    var maxOutputTokens: Int?
    var inputCostPerToken: Double?
    var outputCostPerToken: Double?

    // MARK: - Init

    init(
        id: String,
        ownedBy: String = "",
        capabilities: [Capability] = [],
        provider: Provider = .cloud,
        mode: Mode = .chat,
        providerName: String = "",
        maxInputTokens: Int? = nil,
        maxOutputTokens: Int? = nil,
        inputCostPerToken: Double? = nil,
        outputCostPerToken: Double? = nil
    ) {
        self.id = id
        self.ownedBy = ownedBy
        self.capabilities = capabilities
        self.provider = provider
        self.mode = mode
        self.providerName = providerName
        self.maxInputTokens = maxInputTokens
        self.maxOutputTokens = maxOutputTokens
        self.inputCostPerToken = inputCostPerToken
        self.outputCostPerToken = outputCostPerToken
    }

    var logoImageName: String? {
        switch providerName {
        case "OpenAI": "openai"
        case "Anthropic": "anthropic"
        case "Ollama": "ollama"
        case "Google": "gemini"
        case "DeepSeek": "deepseek"
        case "vLLM": "vllm"
        default: nil
        }
    }
}

// MARK: - Image and vision support

extension LLMModel {
    nonisolated var supportsNativeVision: Bool {
        capabilities.contains(.vision)
    }

    nonisolated var supportsNativeImageGeneration: Bool {
        mode == .imageGeneration || capabilities.contains(.imageGeneration)
    }

    nonisolated var isVisionSpecialist: Bool {
        supportsNativeVision && (mode == .chat || mode == .completion || mode == .unknown)
    }

    // Dedicated models use the images endpoint; capable chat models keep the chat transport.
    nonisolated var isImageGenerationSpecialist: Bool {
        mode == .imageGeneration || (
            capabilities.contains(.imageGeneration) && (mode == .chat || mode == .completion || mode == .unknown)
        )
    }
}

// MARK: - Provider

extension LLMModel {
    enum Provider: Equatable, Sendable {
        case local
        case cloud

        // MARK: - Properties

        var label: String {
            switch self {
            case .local: String(localized: "Local")
            case .cloud: String(localized: "Cloud")
            }
        }

        var icon: String {
            switch self {
            case .local: "desktopcomputer"
            case .cloud: "cloud"
            }
        }

        var genericLogoSystemName: String {
            switch self {
            case .local: "cpu.fill"
            case .cloud: "sparkles"
            }
        }

        // MARK: - Static

        static func from(_ providerString: String?) -> Provider {
            let localProviders: Set<String> = [
                "ollama", "ollama_chat", "lm_studio", "llamacpp", "hosted_vllm", "vllm"
            ]
            guard let value = providerString?.lowercased() else { return .cloud }
            return localProviders.contains(value) ? .local : .cloud
        }

        static func displayName(from providerString: String?) -> String {
            guard let key = providerString?.lowercased() else { return "" }
            let mapping: [String: String] = [
                "openai": "OpenAI",
                "anthropic": "Anthropic",
                "ollama": "Ollama",
                "vertex_ai": "Google",
                "vertex_ai_beta": "Google",
                "gemini": "Google",
                "deepseek": "DeepSeek",
                "cohere": "Cohere",
                "mistral": "Mistral",
                "groq": "Groq",
                "ollama_chat": "Ollama",
                "azure": "Azure",
                "azure_ai": "Azure",
                "bedrock": "AWS Bedrock",
                "lm_studio": "LM Studio",
                "llamacpp": "llama.cpp",
                "hosted_vllm": "vLLM",
                "vllm": "vLLM",
                "replicate": "Replicate",
                "huggingface": "Hugging Face",
                "together_ai": "Together AI",
                "fireworks_ai": "Fireworks AI",
                "perplexity": "Perplexity",
                "anyscale": "Anyscale",
                "xai": "xAI"
            ]
            return mapping[key] ?? providerString ?? ""
        }
    }
}

// MARK: - Apple native

extension LLMModel {
    static let appleSpeechRecognition = LLMModel(
        id: "apple-speech-recognition",
        provider: .local,
        mode: .audioTranscription,
        providerName: "Apple"
    )

    var isAppleNative: Bool {
        id == LLMModel.appleSpeechRecognition.id
    }
}

// MARK: - Mode

extension LLMModel {
    enum Mode: String, Equatable, Sendable {
        case chat
        case completion
        case embedding
        case imageGeneration = "image_generation"
        case audioTranscription = "audio_transcription"
        case audioSpeech = "audio_speech"
        case unknown

        // MARK: - Init

        init(rawString: String?) {
            guard let rawString else {
                self = .chat
                return
            }
            self = Mode(rawValue: rawString) ?? .unknown
        }
    }
}

// MARK: - Capability

extension LLMModel {
    enum Capability: String, Equatable, Sendable, CaseIterable {
        case text
        case vision
        case functionCalling
        case parallelFunctionCalling
        case jsonSchema
        case webSearch
        case thinking
        case audioInput
        case imageGeneration

        // MARK: - Properties

        var label: String {
            switch self {
            case .text:
                String(localized: "tag.text")
            case .vision:
                String(localized: "tag.vision")
            case .functionCalling:
                String(localized: "tag.tools")
            case .parallelFunctionCalling:
                String(localized: "tag.parallel.tools")
            case .jsonSchema:
                String(localized: "tag.JSON.mode")
            case .webSearch:
                String(localized: "tag.web.search")
            case .thinking:
                String(localized: "tag.thinking")
            case .audioInput:
                String(localized: "tag.audio")
            case .imageGeneration:
                String(localized: "tag.image.generation")
            }
        }

        var icon: String {
            switch self {
            case .text: "text.bubble"
            case .vision: "eye"
            case .functionCalling: "wrench.and.screwdriver"
            case .parallelFunctionCalling: "square.stack.3d.up"
            case .jsonSchema: "curlybraces"
            case .webSearch: "globe"
            case .thinking: "brain"
            case .audioInput: "waveform"
            case .imageGeneration: "photo.artframe"
            }
        }

        var color: Color {
            switch self {
            case .text: .secondary
            case .vision: .purple
            case .functionCalling: .orange
            case .parallelFunctionCalling: .cyan
            case .jsonSchema: .green
            case .webSearch: .blue
            case .thinking: .indigo
            case .audioInput: .pink
            case .imageGeneration: .mint
            }
        }
    }
}
