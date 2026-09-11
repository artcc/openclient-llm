//
//  ChatViewModel+BuiltInTools.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 11/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

extension ChatViewModel {
    func observeBuiltInToolSettingsChanges() {
        builtInToolSettingsObservationTask?.cancel()
        builtInToolSettingsObservationTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(named: .builtInToolSettingsDidChange)
            for await _ in notifications {
                guard let self else { return }
                guard case .loaded(var loadedState) = state else { continue }
                refreshContextUsage(in: &loadedState)
                state = .loaded(loadedState)
            }
        }
    }
}
