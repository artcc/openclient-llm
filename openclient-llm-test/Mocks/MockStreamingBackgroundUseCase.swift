//
//  MockStreamingBackgroundUseCase.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 27/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation
@testable import openclient_llm

@MainActor
final class MockStreamingBackgroundUseCase: StreamingBackgroundUseCaseProtocol {
    // MARK: - Properties

    private(set) var beginCallCount = 0
    private(set) var phases: [StreamingBackgroundPhase] = []
    private(set) var completionResults: [Bool] = []
    var onEnd: ((Bool) -> Void)?
    private var expirationHandler: (@MainActor @Sendable () -> Void)?
    private(set) var isActive = false
    var shouldSendCompletionNotification = true

    // MARK: - StreamingBackgroundUseCaseProtocol

    func begin(expirationHandler: @escaping @MainActor @Sendable () -> Void) {
        guard !isActive else { return }
        isActive = true
        beginCallCount += 1
        self.expirationHandler = expirationHandler
    }

    func update(_ phase: StreamingBackgroundPhase) {
        phases.append(phase)
    }

    func end(success: Bool) {
        guard isActive else { return }
        isActive = false
        completionResults.append(success)
        expirationHandler = nil
        onEnd?(success)
    }

    // MARK: - Test helpers

    func expire() {
        guard isActive else { return }
        isActive = false
        let expirationHandler = expirationHandler
        self.expirationHandler = nil
        expirationHandler?()
    }
}
