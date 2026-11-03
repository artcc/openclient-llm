//
//  SettingsManager+ModelCapabilities.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 03/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import CryptoKit
import Foundation

extension SettingsManager {
    private static let modelCapabilityOverridePrefix = "modelCapabilityOverride."

    func getModelCapabilityOverride(for modelId: String, serverBaseURL: String) -> [LLMModel.Capability]? {
        let key = Self.modelCapabilityOverrideKey(for: modelId, serverBaseURL: serverBaseURL)
        guard let values = defaults.stringArray(forKey: key) else { return nil }
        return values.compactMap(LLMModel.Capability.init(rawValue:))
    }

    func setModelCapabilityOverride(
        _ capabilities: [LLMModel.Capability]?, for modelId: String, serverBaseURL: String
    ) {
        let key = Self.modelCapabilityOverrideKey(for: modelId, serverBaseURL: serverBaseURL)
        if let capabilities {
            defaults.set(capabilities.map(\.rawValue), forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func resetModelCapabilityOverrides() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.modelCapabilityOverridePrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private static func modelCapabilityOverrideKey(for modelId: String, serverBaseURL: String) -> String {
        let components = [MCPToolInfo.normalizedServerURL(serverBaseURL), modelId]
        let payload = components.map { Data($0.utf8).base64EncodedString() }.joined(separator: ":")
        let digest = SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
        return modelCapabilityOverridePrefix + digest
    }
}
