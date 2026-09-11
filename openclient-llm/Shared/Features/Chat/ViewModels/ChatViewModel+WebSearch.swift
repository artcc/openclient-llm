//
//  ChatViewModel+WebSearch.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 05/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

// MARK: - Web Search helpers

extension ChatViewModel {
    func toggleWebSearch() {
        guard case .loaded(var loadedState) = state,
              loadedState.selectedModel?.capabilities.contains(.functionCalling) == true,
              settingsManager.getIsBuiltInToolEnabled(.webSearch),
              loadedState.isWebSearchToolConfigured else { return }
        let newValue = !loadedState.isWebSearchEnabled
        setWebSearchEnabledUseCase.execute(newValue)
        loadedState.isWebSearchEnabled = newValue
        refreshContextUsage(in: &loadedState)
        state = .loaded(loadedState)
        LogManager.debug("webSearch toggled: \(newValue)")
    }
}
