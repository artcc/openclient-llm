//
//  MockAgentStreamUseCase.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 05/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation
@testable import openclient_llm

// Safety: Only used within serialized @MainActor test methods.
final class MockAgentStreamUseCase: AgentStreamUseCaseProtocol, @unchecked Sendable {
    // MARK: - Properties

    var events: [AgentEvent] = []
    var error: Error?
    var receivedMessages: [[ChatMessage]] = []
    var receivedToolNames: [String] = []
    private(set) var receivedToolContext: AgentToolContext?
    var onExecute: (() -> Void)?
    var waitsForCancellation = false
    private(set) var executeCallCount = 0
    private(set) var didTerminate = false
    private var activeContinuation: AsyncThrowingStream<AgentEvent, Error>.Continuation?

    // MARK: - Execute

    func execute(
        messages: [ChatMessage],
        model: String,
        parameters: ModelParameters,
        contextWindowTokens: Int?,
        toolContext: AgentToolContext
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        receivedToolContext = toolContext
        executeCallCount += 1
        receivedMessages.append(messages)
        receivedToolNames = toolContext.toolRegistry.definitions.map(\.function.name)
        onExecute?()
        let events = events
        let error = error
        return AsyncThrowingStream { continuation in
            if waitsForCancellation {
                for event in events {
                    continuation.yield(event)
                }
                activeContinuation = continuation
                continuation.onTermination = { [weak self] _ in
                    Task { @MainActor in
                        self?.didTerminate = true
                        self?.activeContinuation = nil
                    }
                }
                return
            }
            Task {
                for event in events {
                    continuation.yield(event)
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
