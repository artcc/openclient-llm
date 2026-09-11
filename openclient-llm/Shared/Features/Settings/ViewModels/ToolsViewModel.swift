//
//  ToolsViewModel.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 11/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

@Observable
@MainActor
final class ToolsViewModel {
    enum Event {
        case viewAppeared
        case toolToggled(BuiltInTool, enabled: Bool)
    }

    enum State: Equatable {
        case loading
        case loaded(LoadedState)
    }

    struct LoadedState: Equatable {
        var enabledTools: Set<BuiltInTool>
    }

    private(set) var state: State = .loading
    private let settingsManager: SettingsManagerProtocol

    init(settingsManager: SettingsManagerProtocol = SettingsManager()) {
        self.settingsManager = settingsManager
    }

    func send(_ event: Event) {
        switch event {
        case .viewAppeared:
            loadSettings()
        case .toolToggled(let tool, let enabled):
            settingsManager.setIsBuiltInToolEnabled(enabled, for: tool)
            loadSettings()
        }
    }

    private func loadSettings() {
        state = .loaded(LoadedState(enabledTools: Set(
            BuiltInTool.allCases.filter { settingsManager.getIsBuiltInToolEnabled($0) }
        )))
    }
}
