//
//  MockAudioRecorderManager.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 05/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation
@testable import openclient_llm

@MainActor
final class MockAudioRecorderManager: AudioRecorderManagerProtocol {
    // MARK: - Properties

    private(set) var isRecording: Bool = false
    private(set) var recordingDuration: TimeInterval = 0

    var startRecordingCalled = false
    var stopRecordingCalled = false
    var cancelRecordingCalled = false

    var stopRecordingResult: (data: Data?, duration: TimeInterval) = (nil, 0)

    // MARK: - AudioRecorderManagerProtocol

    func startRecording() async throws {
        startRecordingCalled = true
        isRecording = true
    }

    func stopRecording() throws -> (data: Data?, duration: TimeInterval) {
        stopRecordingCalled = true
        isRecording = false
        recordingDuration = 0
        return stopRecordingResult
    }

    func cancelRecording() {
        cancelRecordingCalled = true
        isRecording = false
        recordingDuration = 0
    }
}
