//
//  AgentStreamUseCaseExecutionTimeTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class AgentStreamUseCaseExecutionTimeTests: XCTestCase {
    func test_execute_defaultAdditionalTime_preservesCustomImmediateTimeout() async {
        // Given
        let sut = AgentStreamUseCase(repository: MockChatRepository(), timeout: .zero, chunkDelay: .zero)
        let context = AgentToolContext(toolRegistry: ToolRegistry(tools: []))

        // When
        let error = await executionError(sut, context: context)

        // Then
        XCTAssertEqual(context.additionalExecutionTime, .zero)
        XCTAssertEqual(error as? AgentStreamError, .timedOut)
    }

    func test_execute_additionalTime_extendsImmediateTimeoutThroughFinalResponse() async throws {
        // Given
        let sut = AgentStreamUseCase(repository: MockChatRepository(), timeout: .zero, chunkDelay: .zero)
        let context = AgentToolContext(toolRegistry: ToolRegistry(tools: []), additionalExecutionTime: .seconds(600))
        var didComplete = false
        var tokens = ""

        // When
        for try await event in sut.execute(
            messages: [ChatMessage(role: .user, content: "Hello")],
            model: "test",
            parameters: .default,
            toolContext: context
        ) {
            if case .completed = event { didComplete = true }
            if case .token(let text) = event { tokens += text }
        }

        // Then
        XCTAssertTrue(didComplete)
        XCTAssertEqual(tokens, "Mock answer")
    }

    func test_execute_additionalTimeExactlyOffsetsExpiredBudget_addsRatherThanReplacesTimeout() async {
        // Given
        // The zero-sum boundary exercises addition without waiting for a real clock deadline.
        let sut = AgentStreamUseCase(repository: MockChatRepository(), timeout: .seconds(-600), chunkDelay: .zero)
        let context = AgentToolContext(toolRegistry: ToolRegistry(tools: []), additionalExecutionTime: .seconds(600))

        // When
        let error = await executionError(sut, context: context)

        // Then
        XCTAssertEqual(error as? AgentStreamError, .timedOut)
    }

    private func executionError(_ sut: AgentStreamUseCase, context: AgentToolContext) async -> Error? {
        do {
            for try await _ in sut.execute(
                messages: [ChatMessage(role: .user, content: "Hello")],
                model: "test",
                parameters: .default,
                toolContext: context
            ) {}
            XCTFail("Expected timeout")
            return nil
        } catch {
            return error
        }
    }
}
