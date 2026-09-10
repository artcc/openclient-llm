//
//  GenerateImageToolLifecycleTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class GenerateImageToolLifecycleTests: XCTestCase {
    func test_execute_suspendedAttemptCallback_reservesBeforeCheckpointAndWaitsBeforeRequest() async throws {
        // Given
        let useCase = MockGenerateImageUseCase()
        useCase.result = .success(GeneratedImage(data: Data([1]), mimeType: "image/png", revisedPrompt: nil))
        let started = expectation(description: "Attempt checkpoint started")
        let checkpoint = AttemptCheckpoint()
        let sut = GenerateImageTool(modelId: "generator", generateImageUseCase: useCase, onAttempt: {
            checkpoint.callCount += 1
            await withCheckedContinuation { continuation in
                checkpoint.continuation = continuation
                started.fulfill()
            }
        })

        // When
        let task = Task { try await sut.execute(arguments: #"{"prompt":"A cat"}"#) }
        await fulfillment(of: [started], timeout: 1)
        defer { checkpoint.resume(); task.cancel() }

        // Then
        XCTAssertFalse(sut.isAvailableForAdvertisement)
        XCTAssertEqual(useCase.executeCallCount, 0)
        do {
            _ = try await sut.execute(arguments: #"{"prompt":"Another cat"}"#)
            XCTFail("Expected a reserved attempt during checkpointing")
        } catch {
            XCTAssertEqual(error as? GenerateImageTool.ExecutionError, .turnLimitReached)
        }
        checkpoint.resume()
        _ = try await task.value
        XCTAssertEqual(checkpoint.callCount, 1)
        XCTAssertEqual(useCase.executeCallCount, 1)
    }

    func test_execute_invalidArguments_doesNotNotifyAttempt() async {
        // Given
        let useCase = MockGenerateImageUseCase()
        let checkpoint = AttemptCheckpoint()
        let sut = GenerateImageTool(modelId: "generator", generateImageUseCase: useCase, onAttempt: {
            checkpoint.callCount += 1
        })

        // When
        for input in ["not-json", #"{"prompt":" "}"#, #"{"prompt":"Cat","extra":"value"}"#] {
            do {
                _ = try await sut.execute(arguments: input)
                XCTFail("Expected invalid arguments")
            } catch {
                XCTAssertNotNil(error as? GenerateImageTool.ExecutionError)
            }
        }

        // Then
        XCTAssertEqual(checkpoint.callCount, 0)
        XCTAssertEqual(useCase.executeCallCount, 0)
        XCTAssertTrue(sut.isAvailableForAdvertisement)
    }

    func test_execute_callbackCancellation_propagatesWithoutRequest() async {
        // Given
        let useCase = MockGenerateImageUseCase()
        let sut = GenerateImageTool(modelId: "generator", generateImageUseCase: useCase, onAttempt: {
            throw CancellationError()
        })

        // When
        do {
            _ = try await sut.execute(arguments: #"{"prompt":"A cat"}"#)
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        // Then
        XCTAssertEqual(useCase.executeCallCount, 0)
        XCTAssertFalse(sut.isAvailableForAdvertisement)
    }

    func test_execute_configurationChangesDuringCallback_rechecksBeforeRequest() async {
        // Given
        let useCase = MockGenerateImageUseCase()
        let checkpoint = AttemptCheckpoint()
        let sut = GenerateImageTool(
            modelId: "generator", generateImageUseCase: useCase,
            onAttempt: { checkpoint.isAvailable = false },
            isAvailable: { checkpoint.isAvailable }
        )

        // When
        do {
            _ = try await sut.execute(arguments: #"{"prompt":"A cat"}"#)
            XCTFail("Expected changed availability to block the request")
        } catch {
            XCTAssertEqual(error as? GenerateImageTool.ExecutionError, .unavailable)
        }

        // Then
        XCTAssertEqual(useCase.executeCallCount, 0)
        checkpoint.isAvailable = true
        XCTAssertFalse(sut.isAvailableForAdvertisement)
    }

    func test_execute_cancelledDuringCallback_rechecksBeforeRequest() async {
        // Given
        let useCase = MockGenerateImageUseCase()
        let started = expectation(description: "Attempt checkpoint started")
        let checkpoint = AttemptCheckpoint()
        let sut = GenerateImageTool(modelId: "generator", generateImageUseCase: useCase, onAttempt: {
            await withCheckedContinuation { continuation in
                checkpoint.continuation = continuation
                started.fulfill()
            }
        })

        // When
        let task = Task { try await sut.execute(arguments: #"{"prompt":"A cat"}"#) }
        await fulfillment(of: [started], timeout: 1)
        task.cancel()
        checkpoint.resume()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation after checkpoint")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        // Then
        XCTAssertEqual(useCase.executeCallCount, 0)
        XCTAssertFalse(sut.isAvailableForAdvertisement)
    }
}

@MainActor
private final class AttemptCheckpoint {
    var continuation: CheckedContinuation<Void, Never>?
    var callCount = 0
    var isAvailable = true

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
