//
//  BackgroundTaskManager.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 08/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

// MARK: - BackgroundTaskManagerProtocol

@MainActor
protocol BackgroundTaskManagerProtocol: AnyObject {
    var isUsingContinuedTask: Bool { get }

    func beginTask(title: String, subtitle: String, expirationHandler: @escaping @MainActor @Sendable () -> Void)
    func updateTask(completedUnitCount: Int64, subtitle: String)
    func endTask(success: Bool)
}

// MARK: - BackgroundTaskManager

#if os(iOS)
import BackgroundTasks
import UIKit

// MARK: - System abstractions

@MainActor
protocol ContinuedProcessingTaskProtocol: AnyObject {
    var expirationHandler: (() -> Void)? { get set }
    var progress: Progress { get }

    func updateTitle(_ title: String, subtitle: String)
    func setTaskCompleted(success: Bool)
}

@MainActor
protocol BackgroundTaskSystemProtocol: AnyObject {
    func registerContinuedTask(
        identifier: String,
        launchHandler: @escaping @MainActor (ContinuedProcessingTaskProtocol) -> Void
    ) -> Bool
    func submitContinuedTask(identifier: String, title: String, subtitle: String) throws
    func cancelContinuedTask(identifier: String)
    func beginLegacyTask(
        name: String,
        expirationHandler: @escaping @MainActor @Sendable () -> Void
    ) -> UIBackgroundTaskIdentifier
    func endLegacyTask(_ identifier: UIBackgroundTaskIdentifier)
}

@MainActor
final class BackgroundTaskManager: BackgroundTaskManagerProtocol {
    // MARK: - Properties

    private let system: BackgroundTaskSystemProtocol
    private let identifierProvider: @MainActor () -> String
    private var activeSession: BackgroundTaskSession?

    // MARK: - Init

    convenience init() {
        self.init(system: SystemBackgroundTaskSystem(), identifierProvider: BackgroundTaskManager.makeIdentifier)
    }

    init(system: BackgroundTaskSystemProtocol, identifierProvider: @escaping @MainActor () -> String) {
        self.system = system
        self.identifierProvider = identifierProvider
    }

    // MARK: - Public functions

    var isUsingContinuedTask: Bool {
        activeSession?.isUsingContinuedTask == true
    }

    func beginTask(
        title: String,
        subtitle: String,
        expirationHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        guard activeSession == nil else {
            LogManager.debug("BackgroundTask already running, skipping begin")
            return
        }

        let session = BackgroundTaskSession(
            identifier: identifierProvider(),
            title: title,
            subtitle: subtitle,
            system: system,
            expirationHandler: expirationHandler,
            onTerminal: { [weak self] terminalSession in
                guard self?.activeSession === terminalSession else { return }
                self?.activeSession = nil
            }
        )
        activeSession = session

        let didRegister = system.registerContinuedTask(identifier: session.identifier) { task in
            session.attach(task)
        }
        guard didRegister else {
            LogManager.warning("Continued background task registration failed; using legacy fallback")
            session.startLegacyFallback()
            return
        }

        do {
            try system.submitContinuedTask(identifier: session.identifier, title: title, subtitle: subtitle)
            LogManager.debug("Continued background task submitted")
        } catch {
            LogManager.warning("Continued background task submission failed; using legacy fallback: \(error)")
            session.startLegacyFallback()
        }
    }

    func updateTask(completedUnitCount: Int64, subtitle: String) {
        activeSession?.update(completedUnitCount: completedUnitCount, subtitle: subtitle)
    }

    func endTask(success: Bool) {
        activeSession?.finish(success: success)
    }

    // MARK: - Private

    private static func makeIdentifier() -> String {
        "\(Bundle.main.bundleIdentifier ?? "com.artcc.openclient-llm").streaming.\(UUID().uuidString)"
    }
}

// MARK: - BackgroundTaskSession

@MainActor
private final class BackgroundTaskSession {
    enum State {
        case registered
        case continued(ContinuedProcessingTaskProtocol)
        case legacy(UIBackgroundTaskIdentifier)
        case terminal(success: Bool)
    }

    let identifier: String

    private let title: String
    private let system: BackgroundTaskSystemProtocol
    private let expirationHandler: @MainActor @Sendable () -> Void
    private let onTerminal: (BackgroundTaskSession) -> Void
    private var state: State = .registered
    private var completedUnitCount: Int64 = 5
    private var subtitle: String

    var isUsingContinuedTask: Bool {
        if case .continued = state { true } else { false }
    }

    init(
        identifier: String,
        title: String,
        subtitle: String,
        system: BackgroundTaskSystemProtocol,
        expirationHandler: @escaping @MainActor @Sendable () -> Void,
        onTerminal: @escaping (BackgroundTaskSession) -> Void
    ) {
        self.identifier = identifier
        self.title = title
        self.subtitle = subtitle
        self.system = system
        self.expirationHandler = expirationHandler
        self.onTerminal = onTerminal
    }

    func attach(_ task: ContinuedProcessingTaskProtocol) {
        switch state {
        case .registered:
            state = .continued(task)
            configure(task)
            LogManager.debug("Continued background task started")
        case .terminal(let success):
            configure(task)
            task.expirationHandler = nil
            complete(task, success: success)
        case .legacy, .continued:
            task.setTaskCompleted(success: false)
        }
    }

    func startLegacyFallback() {
        guard case .registered = state else { return }
        system.cancelContinuedTask(identifier: identifier)
        let taskIdentifier = system.beginLegacyTask(name: "LLMStreaming") { [weak self] in
            self?.expire()
        }
        guard case .registered = state else {
            if taskIdentifier != .invalid { system.endLegacyTask(taskIdentifier) }
            return
        }
        state = .legacy(taskIdentifier)
        LogManager.debug("Legacy background task begun id=\(taskIdentifier.rawValue)")
    }

    func update(completedUnitCount newValue: Int64, subtitle newSubtitle: String) {
        if case .terminal = state { return }
        let nextCompletedUnitCount = max(completedUnitCount, min(newValue, 99))
        guard nextCompletedUnitCount != completedUnitCount || newSubtitle != subtitle else { return }
        completedUnitCount = nextCompletedUnitCount
        subtitle = newSubtitle
        if case .continued(let task) = state { applyProgress(to: task) }
    }

    func finish(success: Bool) {
        switch state {
        case .registered:
            state = .terminal(success: success)
            system.cancelContinuedTask(identifier: identifier)
        case .continued(let task):
            state = .terminal(success: success)
            task.expirationHandler = nil
            complete(task, success: success)
        case .legacy(let taskIdentifier):
            state = .terminal(success: success)
            if taskIdentifier != .invalid { system.endLegacyTask(taskIdentifier) }
        case .terminal:
            return
        }
        onTerminal(self)
    }

    private func configure(_ task: ContinuedProcessingTaskProtocol) {
        task.progress.totalUnitCount = 100
        applyProgress(to: task)
        task.expirationHandler = { [weak self] in
            self?.expire()
        }
    }

    private func applyProgress(to task: ContinuedProcessingTaskProtocol) {
        task.progress.completedUnitCount = completedUnitCount
        task.updateTitle(title, subtitle: subtitle)
    }

    private func complete(_ task: ContinuedProcessingTaskProtocol, success: Bool) {
        if success {
            task.progress.completedUnitCount = task.progress.totalUnitCount
        }
        task.setTaskCompleted(success: success)
    }

    private func expire() {
        var continuedTask: ContinuedProcessingTaskProtocol?
        var legacyTaskIdentifier: UIBackgroundTaskIdentifier?
        switch state {
        case .registered:
            state = .terminal(success: false)
            system.cancelContinuedTask(identifier: identifier)
        case .continued(let task):
            state = .terminal(success: false)
            task.expirationHandler = nil
            continuedTask = task
        case .legacy(let taskIdentifier):
            state = .terminal(success: false)
            legacyTaskIdentifier = taskIdentifier
        case .terminal:
            return
        }
        LogManager.warning("Background task expired; cancelling active response")
        expirationHandler()
        continuedTask?.setTaskCompleted(success: false)
        if let legacyTaskIdentifier, legacyTaskIdentifier != .invalid {
            system.endLegacyTask(legacyTaskIdentifier)
        }
        onTerminal(self)
    }
}

// MARK: - SystemBackgroundTaskSystem

@MainActor
private final class SystemBackgroundTaskSystem: BackgroundTaskSystemProtocol {
    func registerContinuedTask(
        identifier: String,
        launchHandler: @escaping @MainActor (ContinuedProcessingTaskProtocol) -> Void
    ) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            MainActor.assumeIsolated {
                guard let continuedTask = task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                launchHandler(SystemContinuedProcessingTask(task: continuedTask))
            }
        }
    }

    func submitContinuedTask(identifier: String, title: String, subtitle: String) throws {
        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: title,
            subtitle: subtitle
        )
        request.strategy = .fail
        try BGTaskScheduler.shared.submit(request)
    }

    func cancelContinuedTask(identifier: String) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }

    func beginLegacyTask(
        name: String,
        expirationHandler: @escaping @MainActor @Sendable () -> Void
    ) -> UIBackgroundTaskIdentifier {
        UIApplication.shared.beginBackgroundTask(withName: name, expirationHandler: expirationHandler)
    }

    func endLegacyTask(_ identifier: UIBackgroundTaskIdentifier) {
        UIApplication.shared.endBackgroundTask(identifier)
    }
}

// MARK: - SystemContinuedProcessingTask

@MainActor
private final class SystemContinuedProcessingTask: ContinuedProcessingTaskProtocol {
    private let task: BGContinuedProcessingTask

    init(task: BGContinuedProcessingTask) {
        self.task = task
    }

    var expirationHandler: (() -> Void)? {
        get { task.expirationHandler }
        set { task.expirationHandler = newValue }
    }

    var progress: Progress { task.progress }

    func updateTitle(_ title: String, subtitle: String) {
        task.updateTitle(title, subtitle: subtitle)
    }

    func setTaskCompleted(success: Bool) {
        task.setTaskCompleted(success: success)
    }
}

#else

/// macOS stub — background tasks are not required on macOS.
@MainActor
final class BackgroundTaskManager: BackgroundTaskManagerProtocol {
    var isUsingContinuedTask: Bool { false }

    func beginTask(
        title: String,
        subtitle: String,
        expirationHandler: @escaping @MainActor @Sendable () -> Void
    ) {}
    func updateTask(completedUnitCount: Int64, subtitle: String) {}
    func endTask(success: Bool) {}
}

#endif
