//
//  ChatViewModel+State.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

extension ChatViewModel {
    enum State: Equatable {
        case loading
        case loaded(LoadedState)
    }

    struct LoadedState: Equatable {
        var conversation: Conversation?
        var messages: [ChatMessage] = []
        var inputText: String = ""
        var inputRevision = 0
        var isStreaming: Bool = false
        var responseRevision = 0
        var streamingRevision = 0
        var selectedModel: LLMModel?
        var availableModels: [LLMModel] = []
        var modelCatalogScope: String?
        var conversationStarters: [ConversationStarter] = []
        var errorMessage: String?
        var systemPrompt: String = ""
        var pendingAttachments: [ChatMessage.Attachment] = []
        var isPreparingAttachment: Bool = false
        var pendingSessionId: UUID = UUID()
        var modelParameters: ModelParameters = .default
        var contextWindowTokens: Int?
        var contextUsage: ContextUsage?
        var isSpeaking: Bool = false
        var speakingMessageId: UUID?
        var isRecording: Bool = false
        var recordingDuration: TimeInterval = 0
        var isTranscribing: Bool = false
        var showTokenUsage: Bool = true
        var ttsModelId: String?
        var transcriptionModelId: String?
        var exportedData: Data?
        var branchedConversation: Conversation?
        var isWebSearchEnabled: Bool = false
        var isWebSearchToolConfigured: Bool = false
        var isSearchingWeb: Bool = false
        var activeToolCallIds: Set<String> = []
        var activeToolNamesById: [String: String] = [:]
        var imageToolModelNames: [String: String] = [:]
        var isMCPSupported: Bool = false
        var availableMCPTools: [MCPToolInfo] = []
        var availableMCPServers: [MCPServerInfo] = []
        var failedMCPServerIds: Set<String> = []
        var enabledMCPToolIds: Set<String> = []
        var mcpToolPermissions: [String: MCPToolPermission] = [:]
        var mcpDiscoveryScope: String?
        var mcpDiscoveryRevision: Int = 0
        var isLoadingMCPTools: Bool = false
        var mcpToolsError: String?
    }
}
