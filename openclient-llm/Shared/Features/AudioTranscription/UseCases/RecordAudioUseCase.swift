//
//  RecordAudioUseCase.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 08/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

@MainActor
protocol RecordAudioUseCaseProtocol: AnyObject {
    var isRecording: Bool { get }
    var recordingDuration: TimeInterval { get }

    func startRecording() async throws
    func stopRecording() throws -> (data: Data?, duration: TimeInterval)
    func cancelRecording()
}

@MainActor
final class RecordAudioUseCase: RecordAudioUseCaseProtocol {
    // MARK: - Properties

    private let manager: AudioRecorderManagerProtocol

    var isRecording: Bool { manager.isRecording }
    var recordingDuration: TimeInterval { manager.recordingDuration }

    // MARK: - Init

    init(manager: AudioRecorderManagerProtocol = AudioRecorderManager()) {
        self.manager = manager
    }

    // MARK: - Execute

    func startRecording() async throws {
        try await manager.startRecording()
    }

    func stopRecording() throws -> (data: Data?, duration: TimeInterval) {
        try manager.stopRecording()
    }

    func cancelRecording() {
        manager.cancelRecording()
    }
}
