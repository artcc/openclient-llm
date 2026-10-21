//
//  SettingsManager+ModelConfiguration.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 21/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

extension SettingsManager {
    private static let modelConfigurationKey = "globalChatModelConfiguration"

    func getGlobalChatModelConfiguration() -> ChatModelConfiguration {
        guard let data = defaults.data(forKey: Self.modelConfigurationKey) else { return .default }
        do {
            return try JSONDecoder().decode(ChatModelConfiguration.self, from: data)
        } catch {
            LogManager.error("Unable to decode global chat model configuration")
            return .default
        }
    }

    func setGlobalChatModelConfiguration(_ configuration: ChatModelConfiguration) {
        do {
            let data = try JSONEncoder().encode(configuration)
            defaults.set(data, forKey: Self.modelConfigurationKey)
            NotificationCenter.default.post(name: .chatModelConfigurationDidChange, object: nil)
        } catch {
            LogManager.error("Unable to encode global chat model configuration")
        }
    }

    func resetGlobalChatModelConfiguration() {
        defaults.removeObject(forKey: Self.modelConfigurationKey)
        NotificationCenter.default.post(name: .chatModelConfigurationDidChange, object: nil)
    }
}
