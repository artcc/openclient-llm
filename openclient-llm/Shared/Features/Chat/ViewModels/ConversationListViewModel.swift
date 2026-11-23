//
//  ConversationListViewModel.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 31/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

@Observable
@MainActor
final class ConversationListViewModel {
    // MARK: - Properties

    enum Event {
        case viewAppeared
        case newConversationTapped
        case newPrivateConversationTapped
        case refreshTapped
        case conversation(ConversationEvent)
        case filter(FilterEvent)
        case backup(BackupEvent)

        static func conversationTapped(_ conversation: Conversation) -> Self { .conversation(.tapped(conversation)) }
        static func deleteConversation(_ id: UUID) -> Self { .conversation(.deleted(id)) }
        static func pinToggled(_ id: UUID) -> Self { .conversation(.pinToggled(id)) }
        static func tagsUpdated(_ id: UUID, _ tags: [ConversationTag]) -> Self { .conversation(.tagsUpdated(id, tags)) }
        static func titleEdited(_ id: UUID, _ title: String) -> Self { .conversation(.titleEdited(id, title)) }
        static func searchChanged(_ query: String) -> Self { .filter(.searchChanged(query)) }
        static func tagFilterChanged(_ tag: String?) -> Self { .filter(.tagChanged(tag)) }
        static var exportBackupTapped: Self { .backup(.exportTapped) }
        static var backupDataConsumed: Self { .backup(.dataConsumed) }
        static func importBackupData(_ data: Data) -> Self { .backup(.imported(data)) }
        static var importResultConsumed: Self { .backup(.resultConsumed) }
        static var errorMessageConsumed: Self { .backup(.errorConsumed) }
        static var backupImportReadFailed: Self { .backup(.readFailed) }
        static var backupExportWriteFailed: Self { .backup(.exportWriteFailed) }
    }

    enum ConversationEvent {
        case tapped(Conversation)
        case deleted(UUID)
        case pinToggled(UUID)
        case tagsUpdated(UUID, [ConversationTag])
        case titleEdited(UUID, String)
    }

    enum BackupEvent {
        case exportTapped
        case dataConsumed
        case imported(Data)
        case resultConsumed
        case errorConsumed
        case readFailed
        case exportWriteFailed
    }

    enum State: Equatable {
        case loading
        case loaded(LoadedState)
    }

    struct LoadedState: Equatable {
        var conversations: [Conversation] = []
        var selectedConversation: Conversation?
        var availableModels: [LLMModel] = []
        var errorMessage: String?
        var searchQuery: String = ""
        var filteredConversations: [Conversation] = []
        var activeTagFilter: String?
        var folderScope: ConversationFolderScope = .all
        var folders: [ConversationFolder] = []
        var folderIDs: [UUID: UUID] = [:]
        var hasLoadedFolders = false
        var searchesAllFolders = false
        var backupData: Data?
        var importResult: ImportConversationsResult?
    }

    private(set) var state: State
    let folderRepository: any ConversationFolderRepositoryProtocol
    var requestedScope: ConversationFolderScope = .all
    var folderLoadID = UUID()
    var folderIssue: FolderIssue?
    var isSavingFolderChange = false
    var moveSelection: Set<UUID>?
    var onNewConversation: ((Conversation) -> Void)?

    private let loadConversationsUseCase: LoadConversationsUseCaseProtocol
    private let deleteConversationUseCase: DeleteConversationUseCaseProtocol
    private let pinConversationUseCase: PinConversationUseCaseProtocol
    private let updateConversationTagsUseCase: UpdateConversationTagsUseCaseProtocol
    private let renameConversationUseCase: RenameConversationUseCaseProtocol
    private let fetchModelsUseCase: FetchModelsUseCaseProtocol
    private let syncConversationsUseCase: SyncConversationsUseCaseProtocol
    private let exportBackupUseCase: ExportBackupUseCaseProtocol
    private let importConversationsUseCase: ImportConversationsUseCaseProtocol
    private let settingsManager: SettingsManagerProtocol
    private let cloudRetryDelays: [Duration]
    var errorDismissTask: Task<Void, Never>?
    var hasStartedInitialLoad = false

    var cloudRetryTask: Task<Void, Never>?
    var onConversationSelected: ((Conversation?) -> Void)?
    var onPrivateChatSelected: (() -> Void)?

    // MARK: - Init

    init(
        state: State = .loading,
        loadConversationsUseCase: LoadConversationsUseCaseProtocol = LoadConversationsUseCase(),
        deleteConversationUseCase: DeleteConversationUseCaseProtocol = DeleteConversationUseCase(),
        pinConversationUseCase: PinConversationUseCaseProtocol = PinConversationUseCase(),
        updateConversationTagsUseCase: UpdateConversationTagsUseCaseProtocol = UpdateConversationTagsUseCase(),
        renameConversationUseCase: RenameConversationUseCaseProtocol = RenameConversationUseCase(),
        fetchModelsUseCase: FetchModelsUseCaseProtocol = FetchModelsUseCase(),
        syncConversationsUseCase: SyncConversationsUseCaseProtocol = SyncConversationsUseCase(),
        exportBackupUseCase: ExportBackupUseCaseProtocol = ExportBackupUseCase(),
        importConversationsUseCase: ImportConversationsUseCaseProtocol = ImportConversationsUseCase(),
        settingsManager: SettingsManagerProtocol = SettingsManager(),
        folderRepository: any ConversationFolderRepositoryProtocol = ConversationFolderRepository(),
        cloudRetryDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8)]
    ) {
        self.state = state
        self.loadConversationsUseCase = loadConversationsUseCase
        self.deleteConversationUseCase = deleteConversationUseCase
        self.pinConversationUseCase = pinConversationUseCase
        self.updateConversationTagsUseCase = updateConversationTagsUseCase
        self.renameConversationUseCase = renameConversationUseCase
        self.fetchModelsUseCase = fetchModelsUseCase
        self.syncConversationsUseCase = syncConversationsUseCase
        self.exportBackupUseCase = exportBackupUseCase
        self.importConversationsUseCase = importConversationsUseCase
        self.settingsManager = settingsManager
        self.folderRepository = folderRepository
        self.cloudRetryDelays = cloudRetryDelays
        observeAppDataReset()
        observeConversationUpdated()
    }

    // MARK: - Input functions

    func updateLoadedState(_ loaded: LoadedState) {
        state = .loaded(loaded)
    }

    func send(_ event: Event) {
        switch event {
        case .viewAppeared:
            loadData()
        case .newConversationTapped:
            createNewConversation()
        case .newPrivateConversationTapped:
            onPrivateChatSelected?()
        case .refreshTapped:
            refresh()
        case .conversation(let event):
            handleConversationEvent(event)
        case .filter(let event):
            handleFilterEvent(event)
        case .backup(let event):
            handleBackupEvent(event)
        }
    }

    func refresh() {
        Task { await synchronizeAndReloadConversations() }
    }

    func refreshAsync() async {
        await synchronizeAndReloadConversations()
    }

    func loadData() {
        guard !hasStartedInitialLoad else { return }
        hasStartedInitialLoad = true
        state = .loading

        Task {
            do {
                let conversations = try await loadConversationsUseCase.executeLocally()
                var loaded = LoadedState(conversations: conversations, folderScope: requestedScope)
                applySearchFilter(&loaded)
                state = .loaded(loaded)
                await reloadFolders()

                // Let SwiftUI render local data before starting iCloud work.
                await Task.yield()
                await synchronizeAndReloadConversations()
            } catch {
                state = .loaded(LoadedState(errorMessage: error.localizedDescription, folderScope: requestedScope))
                scheduleErrorDismiss()
                // Folder metadata has its own store and retry state, even when the history cannot be read.
                await reloadFolders()
                return
            }

            var models: [LLMModel] = []
            do {
                models = try await fetchModelsUseCase.execute()
            } catch {
                // Continue with empty models — user can still view conversations
            }

            guard case .loaded(var loadedState) = state else { return }
            loadedState.availableModels = models
            state = .loaded(loadedState)
        }
    }

    func reloadConversations() async {
        guard case .loaded = state else { return }
        do {
            let conversations = try await loadConversationsUseCase.executeLocally()
            guard case .loaded(var loadedState) = state else { return }
            loadedState.conversations = conversations
            loadedState.errorMessage = nil
            applySearchFilter(&loadedState)
            state = .loaded(loadedState)
        } catch {
            guard case .loaded(var loadedState) = state else { return }
            loadedState.errorMessage = error.localizedDescription
            state = .loaded(loadedState)
            scheduleErrorDismiss()
        }
        await reloadFolders()
    }

    func synchronizeAndReloadConversations(retryAttempt: Int = 0) async {
        let result = await syncConversationsUseCase.execute()
        await reloadConversations()

        guard result == .pendingDownload, retryAttempt < cloudRetryDelays.count else {
            if result != .pendingDownload {
                cloudRetryTask?.cancel()
                cloudRetryTask = nil
            }
            return
        }
        cloudRetryTask?.cancel()
        cloudRetryTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.cloudRetryDelays[retryAttempt])
            guard !Task.isCancelled,
                  self.settingsManager.getIsCloudSyncEnabled() else { return }
            await self.synchronizeAndReloadConversations(retryAttempt: retryAttempt + 1)
        }
    }
}

// MARK: - Private

private extension ConversationListViewModel {
    func handleConversationEvent(_ event: ConversationEvent) {
        switch event {
        case .tapped(let conversation):
            selectConversation(conversation)
        case .deleted(let id):
            Task { await deleteConversation(id) }
        case .pinToggled(let id):
            Task { await togglePin(id) }
        case .tagsUpdated(let id, let tags):
            Task { await updateTags(id, tags: tags) }
        case .titleEdited(let id, let title):
            Task { await renameConversation(id, newTitle: title) }
        }
    }

    func handleFilterEvent(_ event: FilterEvent) {
        switch event {
        case .searchChanged(let query):
            updateSearch(query)
        case .tagChanged(let tag):
            updateTagFilter(tag)
        case .scopeChanged(let scope):
            setFolderScope(scope)
        case .searchAllFolders(let enabled):
            guard case .loaded(var loaded) = state else { return }
            loaded.searchesAllFolders = enabled
            applySearchFilter(&loaded)
            state = .loaded(loaded)
        }
    }

    func handleBackupEvent(_ event: BackupEvent) {
        switch event {
        case .exportTapped:
            Task { await exportBackup() }
        case .dataConsumed:
            clearBackupData()
        case .imported(let data):
            Task { await importBackup(data) }
        case .resultConsumed:
            clearImportResult()
        case .errorConsumed:
            clearErrorMessage()
        case .readFailed:
            showBackupImportReadError()
        case .exportWriteFailed:
            showBackupExportWriteError()
        }
    }

    func createNewConversation() {
        guard case .loaded(let loadedState) = state else { return }

        let savedModelId = settingsManager.getSelectedModelId()
        let modelId = loadedState.availableModels.first(where: { $0.id == savedModelId })?.id
            ?? loadedState.availableModels.first?.id
            ?? savedModelId
            ?? ""

        let conversation = Conversation(modelId: modelId)
        if let onNewConversation {
            onNewConversation(conversation)
        } else {
            onConversationSelected?(conversation)
        }
    }

    func selectConversation(_ conversation: Conversation) {
        guard case .loaded(var loadedState) = state else { return }
        loadedState.selectedConversation = conversation
        state = .loaded(loadedState)
        onConversationSelected?(conversation)
    }

    func deleteConversation(_ id: UUID) async {
        do {
            try await deleteConversationUseCase.execute(id)
            guard case .loaded(var loadedState) = state else { return }
            loadedState.conversations.removeAll { $0.id == id }
            if loadedState.selectedConversation?.id == id {
                loadedState.selectedConversation = nil
                onConversationSelected?(nil)
            }
            applySearchFilter(&loadedState)
            state = .loaded(loadedState)
        } catch {
            guard case .loaded(var loadedState) = state else { return }
            loadedState.errorMessage = error.localizedDescription
            state = .loaded(loadedState)
            scheduleErrorDismiss()
        }
    }

    func updateSearch(_ query: String) {
        guard case .loaded(var loadedState) = state else { return }
        loadedState.searchQuery = query
        applySearchFilter(&loadedState)
        state = .loaded(loadedState)
    }

    func togglePin(_ id: UUID) async {
        guard case .loaded(let initialState) = state,
              let conversation = initialState.conversations.first(where: { $0.id == id }) else { return }
        let newValue = !conversation.isPinned
        do {
            try await pinConversationUseCase.execute(id, isPinned: newValue)
            guard case .loaded(var loadedState) = state,
                  let index = loadedState.conversations.firstIndex(where: { $0.id == id }) else { return }
            loadedState.conversations[index].isPinned = newValue
            applySearchFilter(&loadedState)
            state = .loaded(loadedState)
        } catch {
            guard case .loaded(var loadedState) = state else { return }
            loadedState.errorMessage = error.localizedDescription
            state = .loaded(loadedState)
            scheduleErrorDismiss()
        }
    }

    func updateTags(_ id: UUID, tags: [ConversationTag]) async {
        do {
            let savedTags = try await updateConversationTagsUseCase.execute(id, tags: tags)
            guard case .loaded(var loadedState) = state,
                  let index = loadedState.conversations.firstIndex(where: { $0.id == id }) else { return }
            loadedState.conversations[index].tags = savedTags
            applySearchFilter(&loadedState)
            state = .loaded(loadedState)
        } catch {
            guard case .loaded(var loadedState) = state else { return }
            loadedState.errorMessage = error.localizedDescription
            state = .loaded(loadedState)
            scheduleErrorDismiss()
        }
    }

    func updateTagFilter(_ tag: String?) {
        guard case .loaded(var loadedState) = state else { return }
        loadedState.activeTagFilter = tag
        applySearchFilter(&loadedState)
        state = .loaded(loadedState)
    }

    func renameConversation(_ id: UUID, newTitle: String) async {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              case .loaded(let initialState) = state,
              initialState.conversations.contains(where: { $0.id == id }) else { return }
        do {
            try await renameConversationUseCase.execute(id, newTitle: trimmed)
            guard case .loaded(var loadedState) = state,
                  let index = loadedState.conversations.firstIndex(where: { $0.id == id }) else { return }
            loadedState.conversations[index].title = trimmed
            loadedState.conversations[index].updatedAt = Date()
            applySearchFilter(&loadedState)
            state = .loaded(loadedState)
        } catch {
            guard case .loaded(var loadedState) = state else { return }
            loadedState.errorMessage = error.localizedDescription
            state = .loaded(loadedState)
            scheduleErrorDismiss()
        }
    }

    func exportBackup() async {
        do {
            let data = try await exportBackupUseCase.execute()
            guard case .loaded(var loadedState) = state else { return }
            loadedState.backupData = data
            loadedState.errorMessage = nil
            state = .loaded(loadedState)
        } catch {
            guard case .loaded(var loadedState) = state else { return }
            showError(error, in: &loadedState)
        }
    }

    func clearBackupData() {
        guard case .loaded(var loadedState) = state else { return }
        loadedState.backupData = nil
        state = .loaded(loadedState)
    }

    func importBackup(_ data: Data) async {
        do {
            let result = try await importConversationsUseCase.execute(data)
            let conversations = try await loadConversationsUseCase.executeLocally()
            await reloadFolders()
            guard case .loaded(var loadedState) = state else { return }
            loadedState.conversations = conversations
            loadedState.importResult = result
            loadedState.errorMessage = nil
            applySearchFilter(&loadedState)
            state = .loaded(loadedState)
            NotificationCenter.default.post(name: .conversationDidUpdate, object: nil)
        } catch {
            guard case .loaded(var loadedState) = state else { return }
            showError(error, in: &loadedState)
        }
    }

    func clearImportResult() {
        guard case .loaded(var loadedState) = state else { return }
        loadedState.importResult = nil
        state = .loaded(loadedState)
    }

    func clearErrorMessage() {
        guard case .loaded(var loadedState) = state else { return }
        loadedState.errorMessage = nil
        state = .loaded(loadedState)
    }

    func showBackupImportReadError() {
        guard case .loaded(var loadedState) = state else { return }
        loadedState.errorMessage = String(localized: "Unable to read the backup file.")
        state = .loaded(loadedState)
        scheduleErrorDismiss()
    }

    func showBackupExportWriteError() {
        guard case .loaded(var loadedState) = state else { return }
        loadedState.errorMessage = String(localized: "Unable to save the backup file.")
        state = .loaded(loadedState)
        scheduleErrorDismiss()
    }

    func showError(_ error: Error, in loadedState: inout LoadedState) {
        loadedState.errorMessage = error.localizedDescription
        state = .loaded(loadedState)
        scheduleErrorDismiss()
    }

    func scheduleErrorDismiss() {
        errorDismissTask?.cancel()
        errorDismissTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, case .loaded(var currentState) = state else { return }
            currentState.errorMessage = nil
            state = .loaded(currentState)
        }
    }

}
