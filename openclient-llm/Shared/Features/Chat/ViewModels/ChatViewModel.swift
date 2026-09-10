//
//  ChatViewModel.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

@Observable
@MainActor
final class ChatViewModel {
    // MARK: - Properties

    enum Event {
        case viewAppeared
        case viewDisappeared
        case conversationLoaded(Conversation)
        case inputChanged(String)
        case sendTapped
        case stopStreamingTapped
        case suggestionTapped(String)
        case modelSelected(LLMModel)
        case systemPromptChanged(String)
        case attachmentAdded(data: Data, fileName: String, type: ChatMessage.AttachmentType)
        case attachmentRemoved(UUID)
        case modelParametersChanged(ModelParameters)
        case contextWindowChanged(Int?)
        case speakMessageTapped(ChatMessage)
        case stopSpeakingTapped
        case startRecordingTapped
        case stopRecordingTapped
        case cancelRecordingTapped
        case exportConversation
        case exportDataConsumed
        case regenerateLastResponse
        case editMessage(id: UUID, newContent: String)
        case forkFromMessage(UUID)
        case branchedConversationConsumed
        case webSearchToggled
        case mcpButtonTapped, mcpToolsRefreshed
        case mcpToolToggled(toolId: String, enabled: Bool)
        case mcpToolsToggled(toolIds: [String], enabled: Bool)
        case mcpToolPermissionChanged(toolId: String, permission: MCPToolPermission)
        case mcpToolsPermissionChanged(toolIds: [String], permission: MCPToolPermission)
        case mcpAuthorizationDecision(batchId: UUID, requestId: UUID, decision: MCPToolAuthorizationDecision)
        case mcpAuthorizationSubmitted(batchId: UUID)
        case mcpAuthorizationDismissed(batchId: UUID)
        case toggleFavourite(UUID)
    }

    struct PersistenceResult {
        let didPersist: Bool
        let durableConversation: Conversation?
    }

    var state: State

    var onConversationUpdated: (() -> Void)?
    var onForkCreated: ((Conversation) -> Void)?
    let isPrivateChat: Bool

    private let fetchModelsUseCase: FetchModelsUseCaseProtocol
    let prepareImageAttachmentUseCase: PrepareImageAttachmentUseCaseProtocol
    let attachmentRepository: AttachmentRepositoryProtocol
    let streamMessageUseCase: StreamMessageUseCaseProtocol?
    let generateImageUseCase: GenerateImageUseCaseProtocol
    let imageToolChatRepository: ChatRepositoryProtocol?
    let imageToolGenerationUseCase: GenerateImageUseCaseProtocol?
    let agentStreamUseCase: AgentStreamUseCaseProtocol?
    let webSearchUseCase: WebSearchUseCaseProtocol
    let saveConversationUseCase: SaveConversationUseCaseProtocol
    private let synthesizeSpeechUseCase: SynthesizeSpeechUseCaseProtocol
    let transcribeAudioUseCase: TranscribeAudioUseCaseProtocol
    let exportConversationUseCase: ExportConversationUseCaseProtocol
    let branchConversationUseCase: BranchConversationUseCaseProtocol
    let getChatPreferencesUseCase: GetChatPreferencesUseCaseProtocol
    private let saveSelectedModelUseCase: SaveSelectedModelUseCaseProtocol
    let setWebSearchEnabledUseCase: SetWebSearchEnabledUseCaseProtocol
    let fetchMCPToolsUseCase: FetchMCPToolsUseCaseProtocol
    let settingsManager: SettingsManagerProtocol
    let mcpAuthorizationCoordinator: MCPToolAuthorizationCoordinator
    let resolveAudioModelIdsUseCase: ResolveAudioModelIdsUseCaseProtocol
    let getUserProfileContextUseCase: GetUserProfileContextUseCaseProtocol?
    let getMemoryContextUseCase: GetMemoryContextUseCaseProtocol?
    let memoryManager: MemoryManagerProtocol?
    let getConversationStartersUseCase: GetConversationStartersUseCaseProtocol
    private let playAudioUseCase: any PlayAudioUseCaseProtocol
    let recordAudioUseCase: any RecordAudioUseCaseProtocol
    let triggerHapticFeedbackUseCase: TriggerHapticFeedbackUseCaseProtocol
    let streamingBackgroundUseCase: StreamingBackgroundUseCaseProtocol
    let notifyStreamingCompletedUseCase: NotifyStreamingCompletedUseCaseProtocol
    let compactConversationUseCase: CompactConversationUseCaseProtocol
    var streamTask: Task<Void, Never>?
    @ObservationIgnored var streamingUpdateBuffer = StreamingUpdateBuffer()
    @ObservationIgnored var backgroundPersistenceObserver: NSObjectProtocol?
    var pendingPreflightCompaction: PendingPreflightCompaction?
    var persistenceTask: Task<PersistenceResult, Never>?
    var persistenceBase: Conversation?
    var queuedPersistenceConversation: Conversation?
    var persistenceGeneration = 0
    var persistenceResetGeneration = 0
    private var loadTask: Task<Void, Never>?
    var activeAssistantMessageId: UUID?
    var backgroundPersistenceCheckpointTask: Task<Void, Never>?
    var backgroundPersistenceFingerprint: Int?
    var errorDismissTask: Task<Void, Never>?
    var durationTrackingTask: Task<Void, Never>?
    var mcpSettingsObservationTask: Task<Void, Never>?
    var mcpDiscoveryTask: Task<Void, Never>?
    var mcpDiscoveryGeneration = 0
    var observedMCPAuthorizationScope: String
    private var pendingConversation: Conversation?
    var isPreparingAppHandoff = false
    var attachmentPreparationCount = 0

    // MARK: - Init

    init(
        conversation: Conversation? = nil,
        isPrivateChat: Bool = false,
        state: State = .loading,
        fetchModelsUseCase: FetchModelsUseCaseProtocol = FetchModelsUseCase(),
        prepareImageAttachmentUseCase: PrepareImageAttachmentUseCaseProtocol = PrepareImageAttachmentUseCase(),
        attachmentRepository: AttachmentRepositoryProtocol = AttachmentRepository(),
        streamMessageUseCase: StreamMessageUseCaseProtocol? = nil,
        generateImageUseCase: GenerateImageUseCaseProtocol = GenerateImageUseCase(),
        agentStreamUseCase: AgentStreamUseCaseProtocol? = nil,
        webSearchUseCase: WebSearchUseCaseProtocol = WebSearchUseCase(),
        saveConversationUseCase: SaveConversationUseCaseProtocol = SaveConversationUseCase(),
        synthesizeSpeechUseCase: SynthesizeSpeechUseCaseProtocol = SynthesizeSpeechUseCase(),
        transcribeAudioUseCase: TranscribeAudioUseCaseProtocol = TranscribeAudioUseCase(),
        exportConversationUseCase: ExportConversationUseCaseProtocol = ExportConversationUseCase(),
        branchConversationUseCase: BranchConversationUseCaseProtocol = BranchConversationUseCase(),
        getChatPreferencesUseCase: GetChatPreferencesUseCaseProtocol = GetChatPreferencesUseCase(),
        saveSelectedModelUseCase: SaveSelectedModelUseCaseProtocol = SaveSelectedModelUseCase(),
        setWebSearchEnabledUseCase: SetWebSearchEnabledUseCaseProtocol = SetWebSearchEnabledUseCase(),
        fetchMCPToolsUseCase: FetchMCPToolsUseCaseProtocol = FetchMCPToolsUseCase(),
        settingsManager: SettingsManagerProtocol = SettingsManager(),
        mcpAuthorizationCoordinator: MCPToolAuthorizationCoordinator? = nil,
        resolveAudioModelIdsUseCase: ResolveAudioModelIdsUseCaseProtocol = ResolveAudioModelIdsUseCase(),
        getUserProfileContextUseCase: GetUserProfileContextUseCaseProtocol? = nil,
        getMemoryContextUseCase: GetMemoryContextUseCaseProtocol? = nil,
        memoryManager: MemoryManagerProtocol? = nil,
        getConversationStartersUseCase: GetConversationStartersUseCaseProtocol = GetConversationStartersUseCase(),
        playAudioUseCase: any PlayAudioUseCaseProtocol = PlayAudioUseCase(),
        recordAudioUseCase: any RecordAudioUseCaseProtocol = RecordAudioUseCase(),
        triggerHapticFeedbackUseCase: TriggerHapticFeedbackUseCaseProtocol = TriggerHapticFeedbackUseCase(),
        streamingBackgroundUseCase: StreamingBackgroundUseCaseProtocol = StreamingBackgroundUseCase(),
        notifyStreamingCompletedUseCase: NotifyStreamingCompletedUseCaseProtocol = NotifyStreamingCompletedUseCase(),
        compactConversationUseCase: CompactConversationUseCaseProtocol = CompactConversationUseCase(),
        imageToolChatRepository: ChatRepositoryProtocol? = nil,
        imageToolGenerationUseCase: GenerateImageUseCaseProtocol? = nil
    ) {
        self.state = state
        self.pendingConversation = conversation
        if case .loaded(let loadedState) = state {
            self.persistenceBase = loadedState.conversation ?? conversation
        } else {
            self.persistenceBase = conversation
        }
        self.isPrivateChat = isPrivateChat
        self.fetchModelsUseCase = fetchModelsUseCase
        self.prepareImageAttachmentUseCase = prepareImageAttachmentUseCase
        self.attachmentRepository = attachmentRepository
        self.streamMessageUseCase = streamMessageUseCase
        self.generateImageUseCase = generateImageUseCase
        self.imageToolChatRepository = imageToolChatRepository
        self.imageToolGenerationUseCase = imageToolGenerationUseCase
        self.agentStreamUseCase = agentStreamUseCase
        self.webSearchUseCase = webSearchUseCase
        self.saveConversationUseCase = saveConversationUseCase
        self.synthesizeSpeechUseCase = synthesizeSpeechUseCase
        self.transcribeAudioUseCase = transcribeAudioUseCase
        self.exportConversationUseCase = exportConversationUseCase
        self.branchConversationUseCase = branchConversationUseCase
        self.getChatPreferencesUseCase = getChatPreferencesUseCase
        self.saveSelectedModelUseCase = saveSelectedModelUseCase
        self.setWebSearchEnabledUseCase = setWebSearchEnabledUseCase
        self.fetchMCPToolsUseCase = fetchMCPToolsUseCase
        self.settingsManager = settingsManager
        self.observedMCPAuthorizationScope = settingsManager.getMCPAuthorizationScope()
        self.mcpAuthorizationCoordinator = mcpAuthorizationCoordinator
            ?? MCPToolAuthorizationCoordinator(settingsManager: settingsManager)
        self.resolveAudioModelIdsUseCase = resolveAudioModelIdsUseCase
        self.getUserProfileContextUseCase = getUserProfileContextUseCase ?? (
            isPrivateChat ? nil : GetUserProfileContextUseCase()
        )
        self.getMemoryContextUseCase = getMemoryContextUseCase ?? (
            isPrivateChat ? nil : GetMemoryContextUseCase()
        )
        self.memoryManager = memoryManager ?? (isPrivateChat ? nil : MemoryManager())
        self.getConversationStartersUseCase = getConversationStartersUseCase
        self.playAudioUseCase = playAudioUseCase
        self.recordAudioUseCase = recordAudioUseCase
        self.triggerHapticFeedbackUseCase = triggerHapticFeedbackUseCase
        self.streamingBackgroundUseCase = streamingBackgroundUseCase
        self.notifyStreamingCompletedUseCase = notifyStreamingCompletedUseCase
        self.compactConversationUseCase = compactConversationUseCase
        observeAppDataReset()
        observeMCPToolSettingsChanges()
    }

    isolated deinit {
        streamingUpdateBuffer.flushTask?.cancel()
        backgroundPersistenceCheckpointTask?.cancel()
        if let backgroundPersistenceObserver {
            NotificationCenter.default.removeObserver(backgroundPersistenceObserver)
        }
        mcpSettingsObservationTask?.cancel()
        mcpDiscoveryTask?.cancel()
    }

    // MARK: - Input functions

    func send(_ event: Event) {
        guard !isPreparingAppHandoff else { return }
        if case .viewDisappeared = event {
            stopStreaming()
            loadTask?.cancel()
            loadTask = nil
            return
        }
        sendActiveEvent(event)
    }

    func sendActiveEvent(_ event: Event) {
        switch event {
        case .viewDisappeared:
            return
        case .viewAppeared:
            loadInitialData()
        case .conversationLoaded(let conversation):
            loadConversation(conversation)
        case .inputChanged(let text):
            updateInput(text)
        case .sendTapped:
            sendMessage()
        case .stopStreamingTapped:
            stopStreaming()
        default:
            sendRoutedEvent(event)
        }
    }

    func sendRoutedEvent(_ event: Event) {
        switch event {
        case .suggestionTapped(let prompt):
            handleSuggestionTapped(prompt)
        case .modelSelected,
             .systemPromptChanged,
             .attachmentAdded,
             .attachmentRemoved,
             .modelParametersChanged,
             .contextWindowChanged,
             .speakMessageTapped,
             .stopSpeakingTapped:
            handleConfigurationEvent(event)
        case .startRecordingTapped, .stopRecordingTapped, .cancelRecordingTapped:
            handleRecordingEvent(event)
        case .exportConversation, .exportDataConsumed, .regenerateLastResponse,
             .editMessage, .forkFromMessage, .branchedConversationConsumed, .toggleFavourite:
            handlePhase6Event(event)
        case .webSearchToggled:
            toggleWebSearch()
        case .mcpButtonTapped, .mcpToolsRefreshed, .mcpToolToggled, .mcpToolsToggled,
             .mcpToolPermissionChanged, .mcpToolsPermissionChanged,
             .mcpAuthorizationDecision, .mcpAuthorizationSubmitted, .mcpAuthorizationDismissed:
            handleMCPEvent(event)
        case .viewDisappeared, .viewAppeared, .conversationLoaded, .inputChanged, .sendTapped, .stopStreamingTapped:
            return
        }
    }

    func resetAfterAppDataReset() {
        cancelActiveStreaming(shouldPersist: false)
        persistenceResetGeneration += 1
        persistenceTask?.cancel()
        persistenceTask = nil
        queuedPersistenceConversation = nil
        persistenceBase = nil
        loadInitialData()
    }
}

// MARK: - Private

private extension ChatViewModel {

    func loadInitialData() {
        cancelActiveStreaming()
        loadTask?.cancel()
        state = .loading
        loadTask = Task { await fetchAndBuildInitialState() }
    }

    func fetchAndBuildInitialState() async {
        let catalogScope = settingsManager.getMCPAuthorizationScope()
        var resolvedModels: [LLMModel] = []
        var modelError: String?

        do {
            resolvedModels = try await fetchModelsUseCase.execute()
        } catch {
            modelError = error.localizedDescription
        }

        guard !Task.isCancelled else { return }
        guard catalogScope == settingsManager.getMCPAuthorizationScope() else {
            loadInitialData()
            return
        }
        let pending = pendingConversation
        pendingConversation = nil
        let loadedState = makeLoadedState(
            models: resolvedModels,
            pending: pending,
            errorMessage: modelError
        )
        state = .loaded(loadedState)
        loadTask = nil
        if modelError != nil {
            scheduleErrorDismiss()
        }

        refreshMCPTools()
    }

    func handleConfigurationEvent(_ event: Event) {
        switch event {
        case .modelSelected(let model): selectModel(model)
        case .systemPromptChanged(let prompt): updateSystemPrompt(prompt)
        case .attachmentAdded(let data, let fileName, let type):
            addAttachment(data: data, fileName: fileName, type: type)
        case .attachmentRemoved(let id): removeAttachment(id)
        case .modelParametersChanged(let parameters): updateModelParameters(parameters)
        case .contextWindowChanged(let tokens): updateContextWindow(tokens)
        case .speakMessageTapped(let message): speakMessage(message)
        case .stopSpeakingTapped: stopSpeaking()
        default: break
        }
    }

    func loadConversation(_ conversation: Conversation) {
        cancelActiveStreaming()
        guard case .loaded(var loadedState) = state else {
            pendingConversation = conversation
            return
        }
        persistenceBase = conversation
        loadedState.conversation = conversation
        loadedState.messages = conversation.messages
        loadedState.systemPrompt = conversation.systemPrompt
        loadedState.modelParameters = conversation.modelParameters
        loadedState.contextWindowTokens = conversation.contextWindowTokens
        let selectedModel = loadedState.availableModels.first(where: { $0.id == conversation.modelId })
            ?? loadedState.selectedModel
        loadedState.selectedModel = selectedModel
        loadedState.pendingAttachments = []
        loadedState.inputText = ""
        loadedState.inputRevision += 1
        loadedState.errorMessage = nil
        refreshContextUsage(in: &loadedState)
        state = .loaded(loadedState)
    }

    func selectModel(_ model: LLMModel) {
        guard case .loaded(var loadedState) = state else { return }
        LogManager.info("selectModel id=\(model.id)")
        loadedState.selectedModel = model
        refreshContextUsage(in: &loadedState)
        state = .loaded(loadedState)
        saveSelectedModelUseCase.execute(modelId: model.id)
        if loadedState.conversation != nil {
            loadedState.conversation?.modelId = model.id
            state = .loaded(loadedState)
            scheduleConversationPersistence()
        }
    }

    func updateSystemPrompt(_ prompt: String) {
        guard case .loaded(var loadedState) = state else { return }
        loadedState.systemPrompt = prompt
        if loadedState.conversation != nil {
            loadedState.conversation?.systemPrompt = prompt
        }
        refreshContextUsage(in: &loadedState)
        state = .loaded(loadedState)
        scheduleConversationPersistence()
    }

    func updateModelParameters(_ parameters: ModelParameters) {
        guard case .loaded(var loadedState) = state else { return }
        loadedState.modelParameters = parameters
        if loadedState.conversation != nil {
            loadedState.conversation?.modelParameters = parameters
        }
        state = .loaded(loadedState)
        scheduleConversationPersistence()
    }

    func speakMessage(_ message: ChatMessage) {
        guard case .loaded(var loadedState) = state,
              !message.content.isEmpty else { return }
        guard let ttsModelId = loadedState.ttsModelId else { return }

        loadedState.isSpeaking = true
        loadedState.speakingMessageId = message.id
        state = .loaded(loadedState)
        Task {
            do {
                let audioData = try await synthesizeSpeechUseCase.execute(
                    text: message.content,
                    model: ttsModelId,
                    voice: getChatPreferencesUseCase.getSelectedTTSVoice(forModelId: ttsModelId)
                )
                await playAudioUseCase.play(data: audioData, messageId: message.id)
                guard case .loaded(var currentState) = state else { return }
                currentState.isSpeaking = false
                currentState.speakingMessageId = nil
                state = .loaded(currentState)
            } catch {
                guard case .loaded(var currentState) = state else { return }
                currentState.isSpeaking = false
                currentState.speakingMessageId = nil
                currentState.errorMessage = error.localizedDescription
                state = .loaded(currentState)
                scheduleErrorDismiss()
            }
        }
    }

    func stopSpeaking() {
        playAudioUseCase.stop()
        guard case .loaded(var loadedState) = state else { return }
        loadedState.isSpeaking = false
        loadedState.speakingMessageId = nil
        state = .loaded(loadedState)
    }

    func observeAppDataReset() {
        Task { [weak self] in
            let notifications = NotificationCenter.default
                .notifications(named: .appDataDidReset)
            for await _ in notifications {
                guard let self else { return }
                await MainActor.run {
                    self.resetAfterAppDataReset()
                }
            }
        }
    }

}
