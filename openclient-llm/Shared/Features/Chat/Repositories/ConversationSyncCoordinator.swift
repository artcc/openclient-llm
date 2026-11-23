//
//  ConversationSyncCoordinator.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 10/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

actor ConversationSyncCoordinator {
    struct AdmissionToken: Sendable {
        let generation: Int
    }

    // MARK: - Properties

    private let storage: ConversationStorage
    private var isSynchronizing = false
    private var currentWaiters: [CheckedContinuation<ConversationSyncResult, Never>] = []
    private var followUpWaiters: [CheckedContinuation<ConversationSyncResult, Never>] = []
    private var runTask: Task<Void, Never>?
    private var mutationTasks: [UUID: Task<Conversation?, Error>] = [:]
    private var runGeneration = 0
    private var operationGeneration = 0
    private var isCancelling = false
    private var cancellationFenceCount = 0
    private var cancellationTask: Task<Void, Never>?
    private var admissionWaiters: [CheckedContinuation<AdmissionToken, Never>] = []

    // MARK: - Init

    init(storage: ConversationStorage) {
        self.storage = storage
    }

    // MARK: - Public

    func synchronize() async -> ConversationSyncResult {
        guard !isCancelling else { return .unavailable }
        return await withCheckedContinuation { continuation in
            if isSynchronizing {
                followUpWaiters.append(continuation)
            } else {
                isSynchronizing = true
                currentWaiters.append(continuation)
                startRun()
            }
        }
    }

    func cancel() async {
        if let cancellationTask {
            await cancellationTask.value
            return
        }
        if isCancelling {
            return
        }
        isCancelling = true
        operationGeneration += 1
        runGeneration += 1
        let generation = runGeneration
        let task = runTask
        let mutations = mutationTasks
        task?.cancel()
        for mutation in mutations.values {
            mutation.cancel()
        }
        let cancellationTask = Task {
            await task?.value
            for mutation in mutations.values {
                _ = try? await mutation.value
            }
            self.finishCancellation(generation: generation, mutationIds: Set(mutations.keys))
        }
        self.cancellationTask = cancellationTask
        await cancellationTask.value
    }

    func cancelAndDeleteAll() async throws {
        cancellationFenceCount += 1
        await cancel()
        defer {
            cancellationFenceCount -= 1
            if cancellationFenceCount == 0 {
                reopenAdmission()
            }
        }
        try await storage.deleteAll(synchronize: false)
    }

    func admissionToken() async -> AdmissionToken {
        if !isCancelling {
            return AdmissionToken(generation: operationGeneration)
        }
        return await withCheckedContinuation { continuation in
            admissionWaiters.append(continuation)
        }
    }

    func setPinned(
        _ isPinned: Bool,
        conversationId: UUID,
        synchronize: Bool,
        admissionToken: AdmissionToken
    ) async throws -> Conversation? {
        try await performMutation(admissionToken: admissionToken) { storage in
            try await storage.setPinned(
                isPinned,
                conversationId: conversationId,
                synchronize: synchronize
            )
        }
    }

    func save(
        _ conversation: Conversation,
        expectedBase: Conversation?,
        creationPlacement: ConversationCreationPlacement? = nil,
        synchronize: Bool,
        admissionToken: AdmissionToken
    ) async throws -> Conversation {
        var admissionToken = admissionToken
        var shouldSynchronize = synchronize
        var preservePendingBase = false
        if isCancelling || admissionToken.generation != operationGeneration {
            admissionToken = await self.admissionToken()
            shouldSynchronize = false
            preservePendingBase = true
        }
        guard !isCancelling, admissionToken.generation == operationGeneration else { throw CancellationError() }
        let id = UUID()
        let synchronizeSave = shouldSynchronize
        let shouldPreservePendingBase = preservePendingBase
        let task = Task {
            try await storage.saveSynchronizing(
                conversation,
                expectedBase: expectedBase,
                synchronize: synchronizeSave,
                preservePendingBase: shouldPreservePendingBase,
                creationPlacement: creationPlacement
            )
        }
        mutationTasks[id] = task
        defer { mutationTasks[id] = nil }
        let saved: Conversation?
        do {
            saved = try await task.value
        } catch is CancellationError {
            let retryToken = await self.admissionToken()
            guard retryToken.generation == operationGeneration else { throw CancellationError() }
            saved = try await storage.saveSynchronizing(
                conversation,
                expectedBase: expectedBase,
                synchronize: false,
                preservePendingBase: true,
                creationPlacement: creationPlacement
            )
        }
        guard let saved else { throw CloudSyncError.staleConversationRevision }
        return saved
    }

    func rename(
        _ conversationId: UUID,
        title: String,
        synchronize: Bool,
        admissionToken: AdmissionToken
    ) async throws -> Conversation? {
        try await performMutation(admissionToken: admissionToken) { storage in
            try await storage.rename(conversationId, title: title, synchronize: synchronize)
        }
    }

    func updateTags(
        _ conversationId: UUID,
        tags: [ConversationTag],
        synchronize: Bool,
        admissionToken: AdmissionToken
    ) async throws -> Conversation? {
        try await performMutation(admissionToken: admissionToken) { storage in
            try await storage.updateTags(conversationId, tags: tags, synchronize: synchronize)
        }
    }

    func delete(
        _ conversationId: UUID,
        synchronize: Bool,
        admissionToken: AdmissionToken
    ) async throws {
        _ = try await performMutation(admissionToken: admissionToken) { storage in
            do {
                try await storage.delete(conversationId, synchronize: synchronize)
            } catch {
                throw self.deletionError(from: error)
            }
            return nil
        }
    }

    func deleteAll(
        synchronize: Bool,
        admissionToken: AdmissionToken
    ) async throws {
        _ = try await performMutation(admissionToken: admissionToken) { storage in
            do {
                try await storage.deleteAll(synchronize: synchronize)
            } catch {
                throw self.deletionError(from: error)
            }
            return nil
        }
    }
}

// MARK: - Private

private extension ConversationSyncCoordinator {
    func performMutation(
        admissionToken: AdmissionToken,
        _ operation: @escaping @Sendable (ConversationStorage) async throws -> Conversation?
    ) async throws -> Conversation? {
        guard !isCancelling, admissionToken.generation == operationGeneration else { throw CancellationError() }
        let id = UUID()
        let task = Task {
            try Task.checkCancellation()
            return try await operation(storage)
        }
        mutationTasks[id] = task
        defer { mutationTasks[id] = nil }
        return try await task.value
    }

    nonisolated func deletionError(from error: Error) -> Error {
        switch error {
        case CloudSyncError.requiredDownloadPending:
            ConversationSyncOperationError.pendingDownload
        case CloudSyncError.containerUnavailable, CloudSyncError.containerIdentityChanged:
            ConversationSyncOperationError.unavailable
        default:
            error
        }
    }

    func startRun() {
        let generation = runGeneration
        runTask = Task {
            let result = await storage.synchronize()
            finishRun(with: result, generation: generation)
        }
    }

    func finishRun(with result: ConversationSyncResult, generation: Int) {
        guard generation == runGeneration else { return }
        let completedWaiters = currentWaiters
        currentWaiters = []
        for waiter in completedWaiters {
            waiter.resume(returning: result)
        }

        guard !followUpWaiters.isEmpty else {
            isSynchronizing = false
            runTask = nil
            return
        }
        currentWaiters = followUpWaiters
        followUpWaiters = []
        startRun()
    }

    func finishCancellation(generation: Int, mutationIds: Set<UUID>) {
        guard generation == runGeneration else { return }
        runTask = nil
        cancellationTask = nil
        let waiters = currentWaiters + followUpWaiters
        currentWaiters = []
        followUpWaiters = []
        isSynchronizing = false
        for waiter in waiters {
            waiter.resume(returning: .unavailable)
        }
        for id in mutationIds {
            mutationTasks[id] = nil
        }
        if cancellationFenceCount == 0 {
            reopenAdmission()
        }
    }

    func reopenAdmission() {
        guard isCancelling else { return }
        isCancelling = false
        let waiters = admissionWaiters
        admissionWaiters = []
        let token = AdmissionToken(generation: operationGeneration)
        for waiter in waiters {
            waiter.resume(returning: token)
        }
    }
}
