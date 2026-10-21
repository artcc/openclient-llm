//
//  AppleSpeechRecognitionManager.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 04/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation
import Speech

protocol AppleSpeechRecognitionManagerProtocol: Sendable {
    @MainActor
    func transcribe(audioFileURL: URL) async throws -> String
}

@MainActor
final class AppleSpeechRecognitionManager: AppleSpeechRecognitionManagerProtocol {
    // MARK: - Shared

    static let shared = AppleSpeechRecognitionManager()

    // MARK: - Public

    func transcribe(audioFileURL: URL) async throws -> String {
        try Task.checkCancellation()
        try await requestAuthorization()
        try Task.checkCancellation()

        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw AppleSpeechError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: audioFileURL)
        request.shouldReportPartialResults = false

        let operation = AppleSpeechRecognitionOperation()
        defer { withExtendedLifetime(recognizer) {} }
        return try await operation.run { completion in
            let task = recognizer.recognitionTask(with: request) { result, error in
                completion(result?.bestTranscription.formattedString, result?.isFinal ?? false, error)
            }
            return { task.cancel() }
        }
    }
}

// MARK: - Private

private extension AppleSpeechRecognitionManager {
    func requestAuthorization() async throws {
        let status: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        try Task.checkCancellation()
        guard status == .authorized else {
            throw AppleSpeechError.notAuthorized
        }
    }
}

// MARK: - AppleSpeechError

enum AppleSpeechError: LocalizedError {
    case notAuthorized
    case recognizerUnavailable

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            String(localized: "Speech recognition permission was not granted.")
        case .recognizerUnavailable:
            String(localized: "Speech recognition is not available on this device.")
        }
    }
}
