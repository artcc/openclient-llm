//
//  ChatInputBarState.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 21/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

struct ChatInputBarState: Equatable {
    let inputText: String
    let inputRevision: Int
    let selectedModel: LLMModel?
    let contextUsage: ContextUsage?
    let isStreaming: Bool
    let isRecording: Bool
    let recordingDuration: TimeInterval
    let isTranscribing: Bool
    let isSearchingWeb: Bool
    let activeToolCallIds: Set<String>
    let activeToolNamesById: [String: String]
    let mcpToolDisplayNames: [String: String]
    let isWebSearchEnabled: Bool
    let isWebSearchToolConfigured: Bool
    let isPreparingAttachment: Bool
    let hasPendingAttachments: Bool
    let hasTranscriptionModel: Bool
    let availableMCPToolIds: Set<String>
    let enabledMCPToolIds: Set<String>

    var canAttachImages: Bool {
        canUseChatActions || selectedModel?.capabilities.contains(.vision) == true
    }

    var canUseChatActions: Bool {
        selectedModel?.mode != .imageGeneration
    }

    init(loadedState: ChatViewModel.LoadedState) {
        inputText = loadedState.inputText
        inputRevision = loadedState.inputRevision
        selectedModel = loadedState.selectedModel
        contextUsage = loadedState.contextUsage
        isStreaming = loadedState.isStreaming
        isRecording = loadedState.isRecording
        recordingDuration = loadedState.recordingDuration
        isTranscribing = loadedState.isTranscribing
        isSearchingWeb = loadedState.isSearchingWeb
        activeToolCallIds = loadedState.activeToolCallIds
        activeToolNamesById = loadedState.activeToolNamesById
        isWebSearchEnabled = loadedState.isWebSearchEnabled
        isWebSearchToolConfigured = loadedState.isWebSearchToolConfigured
        isPreparingAttachment = loadedState.isPreparingAttachment
        hasPendingAttachments = !loadedState.pendingAttachments.isEmpty
        hasTranscriptionModel = loadedState.transcriptionModelId != nil
        enabledMCPToolIds = loadedState.enabledMCPToolIds
        availableMCPToolIds = Set(loadedState.availableMCPTools.compactMap { tool in
            guard tool.isInputSchemaSupported,
                  !loadedState.failedMCPServerIds.contains(tool.serverId) else { return nil }
            return tool.id
        })
        mcpToolDisplayNames = loadedState.availableMCPTools.reduce(into: [:]) { names, tool in
            names[tool.prefixedName] = tool.displayName
        }
    }
}
