//
//  StreamingBackgroundUseCaseTests.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 27/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class StreamingBackgroundUseCaseTests: XCTestCase {
    func test_begin_initializesLocalizedContinuedTask() {
        // Given
        let manager = MockBackgroundTaskManager()
        let sut = StreamingBackgroundUseCase(backgroundTaskManager: manager)

        // When
        sut.begin(expirationHandler: {})

        // Then
        XCTAssertEqual(manager.beginCallCount, 1)
        XCTAssertFalse(manager.titles.first?.isEmpty ?? true)
        XCTAssertFalse(manager.subtitles.first?.isEmpty ?? true)
    }

    func test_begin_expiration_invokesForwardedHandler() {
        // Given
        let manager = MockBackgroundTaskManager()
        let sut = StreamingBackgroundUseCase(backgroundTaskManager: manager)
        let probe = ExpirationProbe()
        sut.begin {
            probe.callCount += 1
        }

        // When
        manager.expirationHandler?()

        // Then
        XCTAssertEqual(probe.callCount, 1)
    }

    func test_update_repeatedResponseActivity_advancesProgress() {
        // Given
        let manager = MockBackgroundTaskManager()
        let sut = StreamingBackgroundUseCase(backgroundTaskManager: manager)
        sut.begin(expirationHandler: {})

        // When
        for _ in 0..<16 { sut.update(.responding) }

        // Then
        XCTAssertEqual(manager.progressValues.first, 50)
        XCTAssertEqual(manager.progressValues.last, 51)
    }

    func test_update_agentReturnsToThinking_preservesMonotonicProgress() {
        // Given
        let manager = MockBackgroundTaskManager()
        let sut = StreamingBackgroundUseCase(backgroundTaskManager: manager)
        sut.begin(expirationHandler: {})

        // When
        sut.update(.usingTools)
        sut.update(.thinking)

        // Then
        XCTAssertEqual(manager.progressValues, [65, 65])
        XCTAssertEqual(manager.subtitles.last, StreamingBackgroundPhase.thinking.subtitle)
    }

    func test_end_forwardsResult() {
        // Given
        let manager = MockBackgroundTaskManager()
        let sut = StreamingBackgroundUseCase(backgroundTaskManager: manager)

        // When
        sut.end(success: false)

        // Then
        XCTAssertEqual(manager.completionResults, [false])
    }

    func test_shouldSendCompletionNotification_continuedTaskActive_returnsFalse() {
        // Given
        let manager = MockBackgroundTaskManager()
        manager.isUsingContinuedTask = true
        let sut = StreamingBackgroundUseCase(backgroundTaskManager: manager)

        // When
        let shouldSend = sut.shouldSendCompletionNotification

        // Then
        XCTAssertFalse(shouldSend)
    }

    func test_shouldSendCompletionNotification_legacyFallback_returnsTrue() {
        // Given
        let manager = MockBackgroundTaskManager()
        let sut = StreamingBackgroundUseCase(backgroundTaskManager: manager)

        // When
        let shouldSend = sut.shouldSendCompletionNotification

        // Then
        XCTAssertTrue(shouldSend)
    }
}

@MainActor
private final class MockBackgroundTaskManager: BackgroundTaskManagerProtocol {
    var isUsingContinuedTask = false
    private(set) var beginCallCount = 0
    private(set) var titles: [String] = []
    private(set) var subtitles: [String] = []
    private(set) var progressValues: [Int64] = []
    private(set) var completionResults: [Bool] = []
    private(set) var expirationHandler: (@MainActor @Sendable () -> Void)?

    func beginTask(
        title: String,
        subtitle: String,
        expirationHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        beginCallCount += 1
        titles.append(title)
        subtitles.append(subtitle)
        self.expirationHandler = expirationHandler
    }

    func updateTask(completedUnitCount: Int64, subtitle: String) {
        progressValues.append(completedUnitCount)
        subtitles.append(subtitle)
    }

    func endTask(success: Bool) {
        completionResults.append(success)
    }
}

@MainActor
private final class ExpirationProbe {
    var callCount = 0
}
