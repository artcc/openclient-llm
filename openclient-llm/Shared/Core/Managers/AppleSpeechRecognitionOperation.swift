//
//  AppleSpeechRecognitionOperation.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 21/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

/// Owns the callback bridge and cancellation of a single Speech framework task.
@MainActor
final class AppleSpeechRecognitionOperation {
    typealias Completion = @Sendable (String?, Bool, (any Error)?) -> Void

    private var continuation: CheckedContinuation<String, any Error>?
    private var cancelRecognition: (() -> Void)?

    func run(start: (@escaping Completion) -> (() -> Void)) async throws -> String {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let text: String = try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                cancelRecognition = start { [weak self] text, isFinal, error in
                    Task { @MainActor in
                        self?.receive(text: text, isFinal: isFinal, error: error)
                    }
                }
            }
            try Task.checkCancellation()
            return text
        } onCancel: {
            Task { @MainActor in
                self.finish(.failure(CancellationError()))
            }
        }
    }

    private func receive(text: String?, isFinal: Bool, error: (any Error)?) {
        if let error {
            finish(.failure(error))
        } else if isFinal, let text {
            finish(.success(text))
        }
        // Speech may deliver non-final callbacks even when partial results were not requested.
    }

    private func finish(_ result: Result<String, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        let cancel = cancelRecognition
        cancelRecognition = nil
        cancel?()
        continuation.resume(with: result)
    }
}
