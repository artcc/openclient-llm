//
//  ChatViewModel+StreamingLifecycle.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 14/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

#if os(iOS)
import UIKit
#endif

extension ChatViewModel {
    func cancelActiveStreaming(shouldPersist: Bool = true) {
        mcpAuthorizationCoordinator.cancelPending()
        if let activeAssistantMessageId {
            flushStreamingTextUpdates(for: activeAssistantMessageId)
            rollbackPendingPreflightCompaction(for: activeAssistantMessageId)
        }
        resetStreamingTextUpdates()
        stopBackgroundPersistenceCheckpoints()
        streamTask?.cancel()
        streamTask = nil
        activeAssistantMessageId = nil
        activeModelConfiguration = nil
        defer { streamingBackgroundUseCase.end(success: false) }
        guard case .loaded(var loadedState) = state else { return }
        guard loadedState.isStreaming else { return }
        loadedState.isStreaming = false
        loadedState.isSearchingWeb = false
        loadedState.activeToolCallIds = []
        loadedState.activeToolNamesById = [:]
        refreshContextUsage(in: &loadedState)
        state = .loaded(loadedState)
        if shouldPersist {
            scheduleConversationPersistence()
        }
    }

    func stopStreaming() {
        LogManager.debug("stopStreaming requested")
        cancelActiveStreaming()
    }

    func beginStreamingBackground(for assistantMessageId: UUID) {
        startBackgroundPersistenceCheckpoints(for: assistantMessageId)
        streamingBackgroundUseCase.begin { [weak self] in
            LogManager.warning("Background time expired; saving partial response")
            guard let self, self.activeAssistantMessageId == assistantMessageId else { return }
            self.stopBackgroundPersistenceCheckpoints()
            self.mcpAuthorizationCoordinator.cancelPending()
            self.flushStreamingTextUpdates(for: assistantMessageId)
            self.resetStreamingTextUpdates()
            self.streamTask?.cancel()
            self.streamTask = nil
            self.rollbackPendingPreflightCompaction(for: assistantMessageId)
            self.activeAssistantMessageId = nil
            self.activeModelConfiguration = nil
            guard case .loaded(var currentState) = self.state else { return }
            let wasGenerating = currentState.isStreaming
            if wasGenerating, let index = currentState.messages.firstIndex(where: { $0.id == assistantMessageId }) {
                currentState.messages[index].responseInterruption = .backgroundTaskEnded
            }
            currentState.isStreaming = false
            currentState.isSearchingWeb = false
            currentState.activeToolCallIds = []
            currentState.activeToolNamesById = [:]
            self.refreshContextUsage(in: &currentState)
            self.state = .loaded(currentState)
            self.scheduleConversationPersistence()
            if wasGenerating { self.notifyStreamingCompletedUseCase.executeExpired() }
        }
    }

    private func startBackgroundPersistenceCheckpoints(for assistantMessageId: UUID) {
        stopBackgroundPersistenceCheckpoints()
        backgroundPersistenceFingerprint = nil
        #if os(iOS)
        backgroundPersistenceObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.persistBackgroundCheckpoint(for: assistantMessageId)
            }
        }
        backgroundPersistenceCheckpointTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    return
                }
                guard let self, self.isActiveStream(assistantMessageId) else { return }
                self.persistBackgroundCheckpoint(for: assistantMessageId)
            }
        }
        #endif
    }

    func stopBackgroundPersistenceCheckpoints() {
        backgroundPersistenceCheckpointTask?.cancel()
        backgroundPersistenceCheckpointTask = nil
        if let backgroundPersistenceObserver {
            NotificationCenter.default.removeObserver(backgroundPersistenceObserver)
            self.backgroundPersistenceObserver = nil
        }
        backgroundPersistenceFingerprint = nil
    }

    private func persistBackgroundCheckpoint(for assistantMessageId: UUID) {
        #if os(iOS)
        guard isActiveStream(assistantMessageId), UIApplication.shared.applicationState == .background else { return }
        guard persistenceTask == nil else { return }
        flushStreamingTextUpdates(for: assistantMessageId)
        guard case .loaded(let loadedState) = state else { return }
        let fingerprint = backgroundCheckpointFingerprint(for: loadedState)
        guard fingerprint != backgroundPersistenceFingerprint else { return }
        guard let persistence = scheduleConversationPersistence() else { return }
        Task { @MainActor [weak self] in
            let result = await persistence.value
            guard result.didPersist, let self, self.isActiveStream(assistantMessageId),
                  case .loaded(let currentState) = self.state,
                  self.backgroundCheckpointFingerprint(for: currentState) == fingerprint else { return }
            self.backgroundPersistenceFingerprint = fingerprint
        }
        #endif
    }

    private func backgroundCheckpointFingerprint(for state: LoadedState) -> Int {
        var hasher = Hasher()
        hasher.combine(state.messages.count)
        for message in state.messages {
            hasher.combine(message.id)
            hasher.combine(message.content.count)
            hasher.combine(message.reasoningContent?.count)
            hasher.combine(message.attachments.count)
            hasher.combine(message.tokenUsage?.totalTokens)
        }
        return hasher.finalize()
    }
}
