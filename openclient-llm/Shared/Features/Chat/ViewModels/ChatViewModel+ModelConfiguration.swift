//
//  ChatViewModel+ModelConfiguration.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 21/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

extension ChatViewModel {
    func captureModelConfiguration(for loadedState: LoadedState) -> ChatModelConfiguration {
        let configuration = effectiveModelConfiguration(for: loadedState)
        activeModelConfiguration = configuration
        return configuration
    }

    func finishModelConfiguration() {
        let previousConfiguration = activeModelConfiguration
        activeModelConfiguration = nil
        guard case .loaded(var loadedState) = state, let previousConfiguration else { return }
        let configuration = effectiveModelConfiguration(for: loadedState)
        guard previousConfiguration.contextWindowTokens != configuration.contextWindowTokens else { return }
        refreshContextUsage(in: &loadedState)
        state = .loaded(loadedState)
    }

    func effectiveModelConfiguration(for loadedState: LoadedState) -> ChatModelConfiguration {
        let configuration = loadedState.modelConfiguration
        return configuration.hasCustomValues ? configuration : settingsManager.getGlobalChatModelConfiguration()
    }

    func updateModelConfiguration(_ configuration: ChatModelConfiguration) {
        guard case .loaded(var loadedState) = state else { return }
        loadedState.modelParameters = configuration.parameters
        loadedState.contextWindowTokens = configuration.contextWindowTokens.flatMap { $0 > 0 ? $0 : nil }
        loadedState.conversation?.modelParameters = loadedState.modelParameters
        loadedState.conversation?.contextWindowTokens = loadedState.contextWindowTokens
        refreshContextUsage(in: &loadedState)
        state = .loaded(loadedState)
        scheduleConversationPersistence()
    }

    func observeModelConfigurationChanges() {
        let notifications = NotificationCenter.default.notifications(named: .chatModelConfigurationDidChange)
        modelConfigurationObservationTask = Task { [weak self] in
            for await _ in notifications {
                guard let self else { return }
                guard case .loaded(var loadedState) = state,
                      !loadedState.modelConfiguration.hasCustomValues,
                      !loadedState.isStreaming else { continue }
                refreshContextUsage(in: &loadedState)
                state = .loaded(loadedState)
            }
        }
    }

    var estimatedConversationCost: Double? {
        guard case .loaded(let loadedState) = state,
              let model = loadedState.selectedModel,
              let inputRate = model.inputCostPerToken,
              let outputRate = model.outputCostPerToken,
              inputRate > 0 || outputRate > 0 else { return nil }
        let total = loadedState.messages.compactMap(\.tokenUsage).reduce(0.0) { cost, usage in
            cost + Double(usage.promptTokens) * inputRate + Double(usage.completionTokens) * outputRate
        }
        return total > 0 ? total : nil
    }
}
