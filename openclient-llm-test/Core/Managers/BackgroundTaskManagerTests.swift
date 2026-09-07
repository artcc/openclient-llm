//
//  BackgroundTaskManagerTests.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 27/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import UIKit
import XCTest
@testable import openclient_llm

@MainActor
final class BackgroundTaskManagerTests: XCTestCase {
    func test_beginTask_registrationSucceeds_registersAndSubmitsSameIdentifier() {
        // Given
        let system = MockBackgroundTaskSystem()
        let sut = makeSUT(system: system)

        // When
        sut.beginTask(title: "Title", subtitle: "Preparing", expirationHandler: {})

        // Then
        XCTAssertEqual(system.registeredIdentifiers, ["test.streaming.response"])
        XCTAssertEqual(system.submittedIdentifiers, ["test.streaming.response"])
        XCTAssertEqual(system.submittedTitles, ["Title"])
        XCTAssertEqual(system.submittedSubtitles, ["Preparing"])
        XCTAssertTrue(system.legacyTaskNames.isEmpty)
        XCTAssertFalse(sut.isUsingContinuedTask)
    }

    func test_beginTask_registrationFails_startsLegacyFallback() {
        // Given
        let system = MockBackgroundTaskSystem()
        system.registrationResult = false
        let sut = makeSUT(system: system)

        // When
        sut.beginTask(title: "Title", subtitle: "Preparing", expirationHandler: {})

        // Then
        XCTAssertEqual(system.cancelledIdentifiers, ["test.streaming.response"])
        XCTAssertEqual(system.legacyTaskNames, ["LLMStreaming"])
        XCTAssertTrue(system.submittedIdentifiers.isEmpty)
    }

    func test_beginTask_submissionFails_startsLegacyFallback() {
        // Given
        let system = MockBackgroundTaskSystem()
        system.submissionError = TestError.submissionFailed
        let sut = makeSUT(system: system)

        // When
        sut.beginTask(title: "Title", subtitle: "Preparing", expirationHandler: {})

        // Then
        XCTAssertEqual(system.cancelledIdentifiers, ["test.streaming.response"])
        XCTAssertEqual(system.legacyTaskNames, ["LLMStreaming"])
    }

    func test_endTask_legacyFallback_endsOnce() {
        // Given
        let system = MockBackgroundTaskSystem()
        system.registrationResult = false
        let sut = makeSUT(system: system)
        sut.beginTask(title: "Title", subtitle: "Preparing", expirationHandler: {})

        // When
        sut.endTask(success: true)
        sut.endTask(success: false)

        // Then
        XCTAssertEqual(system.endedLegacyIdentifiers, [system.legacyIdentifier])
    }

    func test_endTask_launchedTask_completesOnceWithProgress() {
        // Given
        let system = MockBackgroundTaskSystem()
        let task = MockContinuedProcessingTask()
        let sut = makeSUT(system: system)
        sut.beginTask(title: "Title", subtitle: "Preparing", expirationHandler: {})
        system.launch(task)
        XCTAssertTrue(sut.isUsingContinuedTask)

        // When
        sut.updateTask(completedUnitCount: 65, subtitle: "Using tools")
        sut.endTask(success: true)
        sut.endTask(success: false)

        // Then
        XCTAssertEqual(task.titles, ["Title", "Title"])
        XCTAssertEqual(task.subtitles, ["Preparing", "Using tools"])
        XCTAssertEqual(task.progress.totalUnitCount, 100)
        XCTAssertEqual(task.progress.completedUnitCount, 100)
        XCTAssertEqual(task.completionResults, [true])
        XCTAssertFalse(sut.isUsingContinuedTask)
    }

    func test_beginTask_activeSession_doesNotReplaceTask() {
        // Given
        let system = MockBackgroundTaskSystem()
        let task = MockContinuedProcessingTask()
        let sut = makeSUT(system: system)
        sut.beginTask(title: "First", subtitle: "Preparing", expirationHandler: {})
        system.launch(task)

        // When
        sut.beginTask(title: "Second", subtitle: "Preparing", expirationHandler: {})
        sut.endTask(success: true)

        // Then
        XCTAssertEqual(system.registeredIdentifiers, ["test.streaming.response"])
        XCTAssertEqual(task.completionResults, [true])
    }

    func test_endTask_beforeLaunch_lateTaskCompletesImmediately() {
        // Given
        let system = MockBackgroundTaskSystem()
        let task = MockContinuedProcessingTask()
        let sut = makeSUT(system: system)
        sut.beginTask(title: "Title", subtitle: "Preparing", expirationHandler: {})

        // When
        sut.endTask(success: true)
        system.launch(task)

        // Then
        XCTAssertEqual(system.cancelledIdentifiers, ["test.streaming.response"])
        XCTAssertEqual(task.completionResults, [true])
        XCTAssertNil(task.expirationHandler)
    }

    func test_expiration_runningTask_invokesHandlerAndCompletesFailureOnce() {
        // Given
        let system = MockBackgroundTaskSystem()
        let task = MockContinuedProcessingTask()
        let sut = makeSUT(system: system)
        let probe = ExpirationProbe()
        sut.beginTask(title: "Title", subtitle: "Preparing") {
            probe.callCount += 1
        }
        system.launch(task)

        // When
        let expirationHandler = task.expirationHandler
        expirationHandler?()
        expirationHandler?()
        sut.endTask(success: true)

        // Then
        XCTAssertEqual(probe.callCount, 1)
        XCTAssertEqual(task.completionResults, [false])
    }

    func test_expiration_afterCompletion_doesNotInvokeHandler() {
        // Given
        let system = MockBackgroundTaskSystem()
        let task = MockContinuedProcessingTask()
        let sut = makeSUT(system: system)
        let probe = ExpirationProbe()
        sut.beginTask(title: "Title", subtitle: "Preparing") {
            probe.callCount += 1
        }
        system.launch(task)
        let expirationHandler = task.expirationHandler

        // When
        sut.endTask(success: true)
        expirationHandler?()

        // Then
        XCTAssertEqual(probe.callCount, 0)
        XCTAssertEqual(task.completionResults, [true])
    }

    func test_expiration_legacyFallback_cleansUpSynchronouslyAndAllowsNextTask() {
        // Given
        let system = MockBackgroundTaskSystem()
        system.registrationResult = false
        var identifiers = ["test.streaming.first", "test.streaming.second"].makeIterator()
        let sut = BackgroundTaskManager(system: system) { identifiers.next() ?? "unexpected" }
        let probe = ExpirationProbe()
        sut.beginTask(title: "First", subtitle: "Preparing") {
            probe.callCount += 1
        }

        // When
        system.expireLegacy()
        sut.beginTask(title: "Second", subtitle: "Preparing", expirationHandler: {})

        // Then
        XCTAssertEqual(probe.callCount, 1)
        XCTAssertEqual(system.endedLegacyIdentifiers, [system.legacyIdentifier])
        XCTAssertEqual(system.legacyTaskNames, ["LLMStreaming", "LLMStreaming"])
    }

    func test_oldLateLaunch_newSessionActive_doesNotCompleteNewTask() {
        // Given
        let system = MockBackgroundTaskSystem()
        var identifiers = ["test.streaming.first", "test.streaming.second"].makeIterator()
        let sut = BackgroundTaskManager(system: system) { identifiers.next() ?? "unexpected" }
        sut.beginTask(title: "First", subtitle: "Preparing", expirationHandler: {})
        let firstLaunch = system.launchHandlers["test.streaming.first"]
        sut.endTask(success: true)
        sut.beginTask(title: "Second", subtitle: "Preparing", expirationHandler: {})
        let oldTask = MockContinuedProcessingTask()
        let newTask = MockContinuedProcessingTask()

        // When
        firstLaunch?(oldTask)
        system.launch(newTask, identifier: "test.streaming.second")
        sut.endTask(success: true)

        // Then
        XCTAssertEqual(oldTask.completionResults, [true])
        XCTAssertEqual(newTask.completionResults, [true])
    }

    func test_duplicateLaunch_continuedTaskActive_rejectsDuplicate() {
        // Given
        let system = MockBackgroundTaskSystem()
        let activeTask = MockContinuedProcessingTask()
        let duplicateTask = MockContinuedProcessingTask()
        let sut = makeSUT(system: system)
        sut.beginTask(title: "Title", subtitle: "Preparing", expirationHandler: {})
        system.launch(activeTask)

        // When
        system.launch(duplicateTask)
        sut.endTask(success: true)

        // Then
        XCTAssertEqual(duplicateTask.completionResults, [false])
        XCTAssertEqual(activeTask.completionResults, [true])
    }

    func test_lateLaunch_legacyFallbackActive_rejectsContinuedTask() {
        // Given
        let system = MockBackgroundTaskSystem()
        system.submissionError = TestError.submissionFailed
        let continuedTask = MockContinuedProcessingTask()
        let sut = makeSUT(system: system)
        sut.beginTask(title: "Title", subtitle: "Preparing", expirationHandler: {})

        // When
        system.launch(continuedTask)
        sut.endTask(success: true)

        // Then
        XCTAssertEqual(continuedTask.completionResults, [false])
        XCTAssertEqual(system.endedLegacyIdentifiers, [system.legacyIdentifier])
    }

    private func makeSUT(system: MockBackgroundTaskSystem) -> BackgroundTaskManager {
        BackgroundTaskManager(system: system, identifierProvider: { "test.streaming.response" })
    }
}

@MainActor
private final class MockBackgroundTaskSystem: BackgroundTaskSystemProtocol {
    var registrationResult = true
    var submissionError: Error?
    var legacyIdentifier = UIBackgroundTaskIdentifier(rawValue: 1)
    private(set) var registeredIdentifiers: [String] = []
    private(set) var submittedIdentifiers: [String] = []
    private(set) var submittedTitles: [String] = []
    private(set) var submittedSubtitles: [String] = []
    private(set) var cancelledIdentifiers: [String] = []
    private(set) var legacyTaskNames: [String] = []
    private(set) var endedLegacyIdentifiers: [UIBackgroundTaskIdentifier] = []
    private(set) var launchHandlers: [String: @MainActor (ContinuedProcessingTaskProtocol) -> Void] = [:]
    private var legacyExpirationHandler: (@MainActor @Sendable () -> Void)?

    func registerContinuedTask(
        identifier: String,
        launchHandler: @escaping @MainActor (ContinuedProcessingTaskProtocol) -> Void
    ) -> Bool {
        registeredIdentifiers.append(identifier)
        launchHandlers[identifier] = launchHandler
        return registrationResult
    }

    func submitContinuedTask(identifier: String, title: String, subtitle: String) throws {
        if let submissionError { throw submissionError }
        submittedIdentifiers.append(identifier)
        submittedTitles.append(title)
        submittedSubtitles.append(subtitle)
    }

    func cancelContinuedTask(identifier: String) {
        cancelledIdentifiers.append(identifier)
    }

    func beginLegacyTask(
        name: String,
        expirationHandler: @escaping @MainActor @Sendable () -> Void
    ) -> UIBackgroundTaskIdentifier {
        legacyTaskNames.append(name)
        legacyExpirationHandler = expirationHandler
        return legacyIdentifier
    }

    func endLegacyTask(_ identifier: UIBackgroundTaskIdentifier) {
        endedLegacyIdentifiers.append(identifier)
    }

    func launch(_ task: ContinuedProcessingTaskProtocol, identifier: String = "test.streaming.response") {
        launchHandlers[identifier]?(task)
    }

    func expireLegacy() {
        legacyExpirationHandler?()
    }
}

@MainActor
private final class MockContinuedProcessingTask: ContinuedProcessingTaskProtocol {
    var expirationHandler: (() -> Void)?
    let progress = Progress(totalUnitCount: 0)
    private(set) var titles: [String] = []
    private(set) var subtitles: [String] = []
    private(set) var completionResults: [Bool] = []

    func updateTitle(_ title: String, subtitle: String) {
        titles.append(title)
        subtitles.append(subtitle)
    }

    func setTaskCompleted(success: Bool) {
        completionResults.append(success)
    }
}

private enum TestError: Error {
    case submissionFailed
}

@MainActor
private final class ExpirationProbe {
    var callCount = 0
}
