//
//  AudioRecorderManager.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 31/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

@MainActor
protocol AudioRecorderManagerProtocol: AnyObject {
    var isRecording: Bool { get }
    var recordingDuration: TimeInterval { get }

    func startRecording() async throws
    func stopRecording() throws -> (data: Data?, duration: TimeInterval)
    func cancelRecording()
}

enum AudioRecordingError: LocalizedError, Equatable {
    case permissionDenied
    case startFailed
    case interrupted
    case readFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            String(localized: "Microphone access is denied. Allow OpenClient to use the microphone in Settings.")
        case .startFailed:
            String(localized: "Audio recording could not start. Check your microphone and try again.")
        case .interrupted:
            String(localized: "Audio recording was interrupted. Please try again.")
        case .readFailed:
            String(localized: "The audio recording could not be read. Please try again.")
        }
    }
}

@MainActor
final class AudioRecorderManager: AudioRecorderManagerProtocol {
    // MARK: - Properties

    private let session: AudioRecordingSessionProtocol
    private var recordingURL: URL?
    private var pendingStartID: UUID?

    var isRecording: Bool { session.isRecording }
    var recordingDuration: TimeInterval { session.currentTime }

    // MARK: - Init

    init(session: AudioRecordingSessionProtocol = AudioRecordingSession()) {
        self.session = session
    }

    isolated deinit {
        cancelRecording()
    }

    // MARK: - Public

    func startRecording() async throws {
        try Task.checkCancellation()
        guard pendingStartID == nil, recordingURL == nil else { throw AudioRecordingError.startFailed }
        let startID = UUID()
        pendingStartID = startID
        defer {
            if pendingStartID == startID { pendingStartID = nil }
        }

        let isAuthorized = await session.requestPermission()
        try Task.checkCancellation()
        guard pendingStartID == startID else { throw CancellationError() }
        guard isAuthorized else { throw AudioRecordingError.permissionDenied }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording_\(UUID().uuidString).m4a")
        recordingURL = url
        do {
            guard try session.record(to: url), session.isRecording else { throw AudioRecordingError.startFailed }
        } catch {
            cancelRecording()
            throw AudioRecordingError.startFailed
        }
    }

    func stopRecording() throws -> (data: Data?, duration: TimeInterval) {
        defer { cancelRecording() }
        guard let url = recordingURL else { return (nil, 0) }
        guard session.isRecording else { throw AudioRecordingError.interrupted }
        // AVAudioRecorder resets currentTime when stopped; capture the actual audio duration first.
        let duration = session.currentTime
        session.stop()
        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else { throw AudioRecordingError.readFailed }
            return (data, duration)
        } catch {
            throw AudioRecordingError.readFailed
        }
    }

    func cancelRecording() {
        pendingStartID = nil
        session.stop()
        guard let url = recordingURL else { return }
        recordingURL = nil
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            // A failed recorder initialization may not have created a file.
        } catch {
            LogManager.error("Failed to remove a temporary audio recording")
        }
    }
}
