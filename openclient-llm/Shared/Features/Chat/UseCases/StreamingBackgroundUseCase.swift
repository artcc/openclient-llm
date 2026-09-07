//
//  StreamingBackgroundUseCase.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 08/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

// MARK: - StreamingBackgroundUseCaseProtocol

@MainActor
protocol StreamingBackgroundUseCaseProtocol: AnyObject {
    var shouldSendCompletionNotification: Bool { get }

    func begin(expirationHandler: @escaping @MainActor @Sendable () -> Void)
    func update(_ phase: StreamingBackgroundPhase)
    func end(success: Bool)
}

extension StreamingBackgroundUseCaseProtocol {
    func end() {
        end(success: true)
    }
}

// MARK: - StreamingBackgroundPhase

enum StreamingBackgroundPhase: Equatable {
    case preparing
    case thinking
    case responding
    case usingTools
    case generatingImage
    case saving

    var completedUnitCount: Int64 {
        switch self {
        case .preparing: 5
        case .thinking: 20
        case .generatingImage: 30
        case .responding: 50
        case .usingTools: 65
        case .saving: 90
        }
    }

    var subtitle: String {
        switch self {
        case .preparing: String(localized: "Preparing your request...")
        case .thinking: String(localized: "Thinking...")
        case .responding: String(localized: "Generating response...")
        case .usingTools: String(localized: "Using tools...")
        case .generatingImage: String(localized: "Generating image...")
        case .saving: String(localized: "Saving response...")
        }
    }
}

// MARK: - StreamingBackgroundUseCase

/// Class-based use case because it wraps a stateful manager (UIBackgroundTaskIdentifier lifecycle).
/// Isolated to @MainActor — safe to call from ChatViewModel without Sendable concerns.
@MainActor
final class StreamingBackgroundUseCase: StreamingBackgroundUseCaseProtocol {
    // MARK: - Properties

    private let backgroundTaskManager: BackgroundTaskManagerProtocol
    private var activityEventCount = 0
    private var reportedProgress: Int64 = 0

    // MARK: - Init

    init(backgroundTaskManager: BackgroundTaskManagerProtocol = BackgroundTaskManager()) {
        self.backgroundTaskManager = backgroundTaskManager
    }

    // MARK: - Execute

    var shouldSendCompletionNotification: Bool {
        !backgroundTaskManager.isUsingContinuedTask
    }

    func begin(expirationHandler: @escaping @MainActor @Sendable () -> Void) {
        activityEventCount = 0
        reportedProgress = StreamingBackgroundPhase.preparing.completedUnitCount
        backgroundTaskManager.beginTask(
            title: String(localized: "Generating response"),
            subtitle: StreamingBackgroundPhase.preparing.subtitle,
            expirationHandler: expirationHandler
        )
    }

    func update(_ phase: StreamingBackgroundPhase) {
        let recordsActivity = phase == .thinking || phase == .responding || phase == .usingTools
        if recordsActivity {
            activityEventCount += 1
        }
        reportedProgress = max(reportedProgress, phase.completedUnitCount)
        if recordsActivity, activityEventCount.isMultiple(of: 16) {
            reportedProgress = min(reportedProgress + 1, 85)
        }
        backgroundTaskManager.updateTask(
            completedUnitCount: reportedProgress,
            subtitle: phase.subtitle
        )
    }

    func end(success: Bool) {
        backgroundTaskManager.endTask(success: success)
    }
}
