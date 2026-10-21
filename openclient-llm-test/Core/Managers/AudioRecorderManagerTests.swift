//
//  AudioRecorderManagerTests.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 21/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class AudioRecorderManagerTests: XCTestCase {
    func test_startRecording_permissionDenied_doesNotAccessRecorder() async {
        let session = RecordingSessionStub()
        session.permission = false
        let sut = AudioRecorderManager(session: session)

        do {
            try await sut.startRecording()
            XCTFail("Expected permission denial")
        } catch {
            XCTAssertEqual(error as? AudioRecordingError, .permissionDenied)
        }

        XCTAssertFalse(sut.isRecording)
        XCTAssertEqual(sut.recordingDuration, 0)
        XCTAssertNil(session.url)
    }

    func test_startRecording_recordReturnsFalse_cleansUpAndThrows() async throws {
        let session = RecordingSessionStub()
        session.recordResult = false
        let sut = AudioRecorderManager(session: session)

        do {
            try await sut.startRecording()
            XCTFail("Expected start failure")
        } catch {
            XCTAssertEqual(error as? AudioRecordingError, .startFailed)
        }

        XCTAssertFalse(sut.isRecording)
        XCTAssertTrue(session.stopCalled)
        let url = try XCTUnwrap(session.url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func test_startRecording_sessionThrows_cleansUpAndAllowsRetry() async throws {
        let session = RecordingSessionStub()
        session.recordError = AudioRecordingError.startFailed
        let sut = AudioRecorderManager(session: session)
        do {
            try await sut.startRecording()
            XCTFail("Expected start failure")
        } catch {
            XCTAssertEqual(error as? AudioRecordingError, .startFailed)
        }
        let failedURL = try XCTUnwrap(session.url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: failedURL.path))

        session.recordError = nil
        try await sut.startRecording()

        XCTAssertTrue(sut.isRecording)
        sut.cancelRecording()
    }

    func test_startRecording_duplicateStart_preservesActiveRecording() async throws {
        let session = RecordingSessionStub()
        let sut = AudioRecorderManager(session: session)
        try await sut.startRecording()
        let url = session.url

        do {
            try await sut.startRecording()
            XCTFail("Expected duplicate start rejection")
        } catch {
            XCTAssertEqual(error as? AudioRecordingError, .startFailed)
        }

        XCTAssertTrue(sut.isRecording)
        XCTAssertEqual(session.url, url)
        XCTAssertFalse(session.stopCalled)
        sut.cancelRecording()
    }

    func test_stopRecording_readsFinalizedAudioAndActualDurationThenRemovesFile() async throws {
        let session = RecordingSessionStub()
        let sut = AudioRecorderManager(session: session)
        try await sut.startRecording()
        session.currentTime = 1.5
        let url = try XCTUnwrap(session.url)

        let result = try sut.stopRecording()

        XCTAssertEqual(result.data, Data([1, 2, 3]))
        XCTAssertEqual(result.duration, 1.5)
        XCTAssertFalse(sut.isRecording)
        XCTAssertEqual(sut.recordingDuration, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(try sut.stopRecording().data)
    }

    func test_stopRecording_interruptedRecorder_stillCleansUp() async throws {
        let session = RecordingSessionStub()
        let sut = AudioRecorderManager(session: session)
        try await sut.startRecording()
        session.isRecording = false
        let url = try XCTUnwrap(session.url)

        XCTAssertThrowsError(try sut.stopRecording()) {
            XCTAssertEqual($0 as? AudioRecordingError, .interrupted)
        }

        XCTAssertTrue(session.stopCalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        try await sut.startRecording()
        XCTAssertTrue(sut.isRecording)
        sut.cancelRecording()
    }

    func test_stopRecording_missingFile_reportsReadErrorAndCleansUp() async throws {
        let session = RecordingSessionStub()
        let sut = AudioRecorderManager(session: session)
        try await sut.startRecording()
        try FileManager.default.removeItem(at: XCTUnwrap(session.url))

        XCTAssertThrowsError(try sut.stopRecording()) {
            XCTAssertEqual($0 as? AudioRecordingError, .readFailed)
        }

        XCTAssertFalse(sut.isRecording)
        XCTAssertEqual(sut.recordingDuration, 0)
    }

    func test_cancelRecording_pendingPermission_preventsLateStart() async {
        let session = RecordingSessionStub()
        let requested = expectation(description: "Permission requested")
        var permission: CheckedContinuation<Bool, Never>?
        session.permissionHandler = {
            await withCheckedContinuation {
                permission = $0
                requested.fulfill()
            }
        }
        let sut = AudioRecorderManager(session: session)
        let task = Task { try await sut.startRecording() }
        await fulfillment(of: [requested], timeout: 2)

        sut.cancelRecording()
        permission?.resume(returning: true)
        do {
            try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        XCTAssertFalse(sut.isRecording)
        XCTAssertNil(session.url)
    }

    func test_startRecording_latePermissionFromCancelledStart_doesNotStopNewRecording() async throws {
        let session = RecordingSessionStub()
        let requested = expectation(description: "First permission requested")
        var permission: CheckedContinuation<Bool, Never>?
        session.permissionHandler = {
            await withCheckedContinuation {
                permission = $0
                requested.fulfill()
            }
        }
        let sut = AudioRecorderManager(session: session)
        let oldTask = Task { try await sut.startRecording() }
        await fulfillment(of: [requested], timeout: 2)
        sut.cancelRecording()
        session.permissionHandler = nil
        try await sut.startRecording()
        let newURL = session.url

        permission?.resume(returning: true)
        do {
            try await oldTask.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        XCTAssertTrue(sut.isRecording)
        XCTAssertEqual(session.url, newURL)
        sut.cancelRecording()
    }

    func test_deinit_activeRecording_stopsCaptureAndRemovesFile() async throws {
        let session = RecordingSessionStub()
        var sut: AudioRecorderManager? = AudioRecorderManager(session: session)
        try await sut?.startRecording()
        let url = try XCTUnwrap(session.url)

        sut = nil

        XCTAssertFalse(session.isRecording)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}

@MainActor
private final class RecordingSessionStub: AudioRecordingSessionProtocol {
    var isRecording = false
    var currentTime: TimeInterval = 0
    var permission = true
    var permissionHandler: (() async -> Bool)?
    var recordResult = true
    var recordError: Error?
    var url: URL?
    var stopCalled = false

    func requestPermission() async -> Bool {
        if let permissionHandler { return await permissionHandler() }
        return permission
    }

    func record(to url: URL) throws -> Bool {
        self.url = url
        try Data([1, 2, 3]).write(to: url)
        if let recordError { throw recordError }
        isRecording = recordResult
        return recordResult
    }

    func stop() {
        stopCalled = true
        isRecording = false
        currentTime = 0
    }
}
