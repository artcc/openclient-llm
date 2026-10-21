//
//  AppleSpeechRecognitionOperationTests.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 21/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class AppleSpeechRecognitionOperationTests: XCTestCase {
    func test_run_backgroundNonFinalCallbacks_waitsForFinalResult() async throws {
        let sut = AppleSpeechRecognitionOperation()
        var cancelled = false

        let text = try await sut.run { completion in
            DispatchQueue.global().async {
                completion("Partial", false, nil)
                completion(nil, false, nil)
                completion("Final text", true, nil)
            }
            return { cancelled = true }
        }

        XCTAssertEqual(text, "Final text")
        XCTAssertTrue(cancelled)
    }

    func test_run_error_releasesRecognitionTask() async {
        let sut = AppleSpeechRecognitionOperation()
        var cancelled = false

        do {
            _ = try await sut.run { completion in
                completion(nil, false, AppleSpeechError.recognizerUnavailable)
                return { cancelled = true }
            }
            XCTFail("Expected recognition failure")
        } catch {
            XCTAssertTrue(error is AppleSpeechError)
        }

        XCTAssertTrue(cancelled)
    }

    func test_run_cancellationWithoutCallback_finishesAndIgnoresLateResult() async {
        let sut = AppleSpeechRecognitionOperation()
        let started = expectation(description: "Recognition started")
        var callback: AppleSpeechRecognitionOperation.Completion?
        var cancelled = false
        let task = Task {
            try await sut.run { completion in
                callback = completion
                started.fulfill()
                return { cancelled = true }
            }
        }
        await fulfillment(of: [started], timeout: 2)

        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        callback?("Late result", true, nil)

        XCTAssertTrue(cancelled)
    }

    func test_run_alreadyCancelled_doesNotStartRecognition() async {
        let sut = AppleSpeechRecognitionOperation()
        var started = false
        let task = Task {
            try await sut.run { _ in
                started = true
                return {}
            }
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertFalse(started)
    }
}
