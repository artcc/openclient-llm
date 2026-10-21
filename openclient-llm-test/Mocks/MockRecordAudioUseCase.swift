//
//  MockRecordAudioUseCase.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 08/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation
@testable import openclient_llm

@MainActor
final class MockRecordAudioUseCase: RecordAudioUseCaseProtocol {
    // MARK: - Properties

    var recordingDuration: TimeInterval = 0
    var isRecording = false

    var startRecordingCalled = false
    var startRecordingCallCount = 0
    var startRecordingHandler: (() async throws -> Void)?
    var startRecordingError: Error?
    var stopRecordingError: Error?
    var stopRecordingCalled = false
    var cancelRecordingCalled = false

    var stopRecordingResult: (data: Data?, duration: TimeInterval) = (nil, 0.0)

    // MARK: - RecordAudioUseCaseProtocol

    func startRecording() async throws {
        startRecordingCalled = true
        startRecordingCallCount += 1
        try await startRecordingHandler?()
        try Task.checkCancellation()
        if let startRecordingError { throw startRecordingError }
        isRecording = true
    }

    func stopRecording() throws -> (data: Data?, duration: TimeInterval) {
        stopRecordingCalled = true
        isRecording = false
        if let stopRecordingError { throw stopRecordingError }
        return stopRecordingResult
    }

    func cancelRecording() {
        cancelRecordingCalled = true
        isRecording = false
    }
}
