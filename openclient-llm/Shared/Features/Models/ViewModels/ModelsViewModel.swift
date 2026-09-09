//
//  ModelsViewModel.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

@Observable
@MainActor
final class ModelsViewModel {
    // MARK: - Properties

    enum Event {
        case viewAppeared
        case refreshTapped
        case modelTapped(LLMModel)
        case ttsModelTapped(LLMModel)
        case sttModelTapped(LLMModel)
        case voiceSelected(String, forModelId: String)
    }

    enum State: Equatable {
        case loading
        case loaded(LoadedState)
    }

    struct LoadedState: Equatable {
        var models: [LLMModel] = []
        var selectedModelId: String?
        var selectedTTSModelId: String?
        var selectedSTTModelId: String?
        var selectedTTSVoices: [String: String] = [:]
        var errorMessage: String?
        var isRefreshing: Bool = false
    }

    private(set) var state: State

    private let fetchModelsUseCase: FetchModelsUseCaseProtocol
    private let settingsManager: SettingsManagerProtocol
    private var errorDismissTask: Task<Void, Never>?

    // MARK: - Init

    init(
        state: State = .loading,
        fetchModelsUseCase: FetchModelsUseCaseProtocol = FetchModelsUseCase(),
        settingsManager: SettingsManagerProtocol = SettingsManager()
    ) {
        self.state = state
        self.fetchModelsUseCase = fetchModelsUseCase
        self.settingsManager = settingsManager
        observeAppDataReset()
    }

    // MARK: - Input functions

    func send(_ event: Event) {
        switch event {
        case .viewAppeared:
            loadModels()
        case .refreshTapped:
            refreshModels()
        case .modelTapped(let model):
            selectModel(model)
        case .ttsModelTapped(let model):
            selectTTSModel(model)
        case .sttModelTapped(let model):
            selectSTTModel(model)
        case .voiceSelected(let voice, let modelId):
            selectVoice(voice, forModelId: modelId)
        }
    }

    func refreshAsync() async {
        guard case .loaded(var loadedState) = state else { return }
        loadedState.isRefreshing = true
        loadedState.errorMessage = nil
        state = .loaded(loadedState)
        await performRefresh()
    }
}

// MARK: - Private

private extension ModelsViewModel {
    func loadModels() {
        state = .loading

        Task {
            do {
                let models = try await fetchModelsUseCase.execute()
                let allModels = [LLMModel.appleSpeechRecognition] + models
                let selectedModelId = settingsManager.getSelectedModelId()
                let selectedTTSModelId = selectDefaultTTSModel(from: allModels)
                let selectedSTTModelId = resolveSelectedSTTModelId(from: allModels)
                let ttsVoices = buildTTSVoices(from: allModels)
                state = .loaded(LoadedState(
                    models: allModels,
                    selectedModelId: selectedModelId,
                    selectedTTSModelId: selectedTTSModelId,
                    selectedSTTModelId: selectedSTTModelId,
                    selectedTTSVoices: ttsVoices
                ))
            } catch {
                state = .loaded(LoadedState(errorMessage: error.localizedDescription))
                scheduleErrorDismiss()
            }
        }
    }

    func refreshModels() {
        guard case .loaded(var loadedState) = state else { return }
        loadedState.isRefreshing = true
        loadedState.errorMessage = nil
        state = .loaded(loadedState)

        Task {
            await performRefresh()
        }
    }

    func selectModel(_ model: LLMModel) {
        guard case .loaded(var loadedState) = state else { return }
        loadedState.selectedModelId = model.id
        state = .loaded(loadedState)
        settingsManager.setSelectedModelId(model.id)
    }

    func selectTTSModel(_ model: LLMModel) {
        guard case .loaded(var loadedState) = state else { return }
        loadedState.selectedTTSModelId = model.id
        state = .loaded(loadedState)
        settingsManager.setSelectedTTSModelId(model.id)
    }

    func selectSTTModel(_ model: LLMModel) {
        guard case .loaded(var loadedState) = state else { return }
        loadedState.selectedSTTModelId = model.id
        state = .loaded(loadedState)
        settingsManager.setSelectedSTTModelId(model.id)
    }

    func selectVoice(_ voice: String, forModelId modelId: String) {
        guard case .loaded(var loadedState) = state else { return }
        loadedState.selectedTTSVoices[modelId] = voice
        state = .loaded(loadedState)
        settingsManager.setSelectedTTSVoice(voice, forModelId: modelId)
    }

    func performRefresh() async {
        do {
            let models = try await fetchModelsUseCase.execute()
            let allModels = [LLMModel.appleSpeechRecognition] + models
            let selectedModelId = settingsManager.getSelectedModelId()
            let selectedTTSModelId = selectDefaultTTSModel(from: allModels)
            let selectedSTTModelId = resolveSelectedSTTModelId(from: allModels)
            let ttsVoices = buildTTSVoices(from: allModels)
            state = .loaded(LoadedState(
                models: allModels,
                selectedModelId: selectedModelId,
                selectedTTSModelId: selectedTTSModelId,
                selectedSTTModelId: selectedSTTModelId,
                selectedTTSVoices: ttsVoices
            ))
        } catch {
            guard case .loaded(var currentState) = state else { return }
            currentState.isRefreshing = false
            currentState.errorMessage = error.localizedDescription
            state = .loaded(currentState)
            scheduleErrorDismiss()
        }
    }

    func selectDefaultTTSModel(from models: [LLMModel]) -> String? {
        let savedModelId = settingsManager.getSelectedTTSModelId()
        if let savedModelId, models.contains(where: { $0.id == savedModelId && $0.mode == .audioSpeech }) {
            return savedModelId
        }
        guard let model = models.first(where: { $0.mode == .audioSpeech }) else { return nil }
        settingsManager.setSelectedTTSModelId(model.id)
        return model.id
    }

    func resolveSelectedSTTModelId(from models: [LLMModel]) -> String {
        let savedModelId = settingsManager.getSelectedSTTModelId()
        if let savedModelId, models.contains(where: {
            $0.id == savedModelId && $0.mode == .audioTranscription
        }) {
            return savedModelId
        }

        let defaultModelId = LLMModel.appleSpeechRecognition.id
        settingsManager.setSelectedSTTModelId(defaultModelId)
        return defaultModelId
    }

    func buildTTSVoices(from models: [LLMModel]) -> [String: String] {
        var voices: [String: String] = [:]
        for model in models where model.mode == .audioSpeech {
            voices[model.id] = settingsManager.getSelectedTTSVoice(forModelId: model.id)
        }
        return voices
    }

    func scheduleErrorDismiss() {
        errorDismissTask?.cancel()
        errorDismissTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, case .loaded(var currentState) = state else { return }
            currentState.errorMessage = nil
            state = .loaded(currentState)
        }
    }

    func observeAppDataReset() {
        Task { [weak self] in
            let notifications = NotificationCenter.default
                .notifications(named: .appDataDidReset)
            for await _ in notifications {
                guard let self else { return }
                await MainActor.run { self.loadModels() }
            }
        }
    }
}
