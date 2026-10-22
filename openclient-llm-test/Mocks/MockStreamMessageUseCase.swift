//
//  MockStreamMessageUseCase.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation
@testable import openclient_llm

// Safety: Only used within serialized @MainActor test methods.
final class MockStreamMessageUseCase: StreamMessageUseCaseProtocol, @unchecked Sendable {
    // MARK: - Properties

    var chunks: [StreamChunk] = []
    var error: Error?
    var tokenDelay: Duration?
    var receivedMessages: [[ChatMessage]] = []
    var receivedParameters: [ModelParameters] = []
    var onExecute: (() -> Void)?

    // MARK: - Execute

    func execute(
        messages: [ChatMessage],
        model: String,
        parameters: ModelParameters
    ) -> AsyncThrowingStream<StreamChunk, Error> {
        receivedMessages.append(messages)
        receivedParameters.append(parameters)
        onExecute?()
        let chunks = chunks
        let error = error
        let tokenDelay = tokenDelay
        return AsyncThrowingStream { continuation in
            Task {
                for chunk in chunks {
                    if let delay = tokenDelay {
                        try? await Task.sleep(for: delay)
                    }
                    continuation.yield(chunk)
                }
                if let error {
                    continuation.finish(throwing: error)
                } else {
                    continuation.finish()
                }
            }
        }
    }
}
