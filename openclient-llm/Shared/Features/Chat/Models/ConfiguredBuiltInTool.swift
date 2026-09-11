//
//  ConfiguredBuiltInTool.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 11/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

struct ConfiguredBuiltInTool: ChatToolProtocol {
    let tool: any ChatToolProtocol
    let settingsManager: SettingsManagerProtocol

    var definition: ToolDefinition { tool.definition }

    var isAvailableForAdvertisement: Bool {
        isEnabled && tool.isAvailableForAdvertisement
    }

    private var isEnabled: Bool {
        guard let identifier = BuiltInTool(rawValue: definition.function.name) else { return false }
        return settingsManager.getIsBuiltInToolEnabled(identifier)
    }

    func execute(arguments: String) async throws -> ToolExecutionResult {
        try Task.checkCancellation()
        guard isEnabled else {
            return ToolExecutionResult(text: "This tool is disabled in OpenClient settings. Do not retry it.")
        }
        return try await tool.execute(arguments: arguments)
    }
}
