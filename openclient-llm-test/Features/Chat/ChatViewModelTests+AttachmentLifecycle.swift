//
//  ChatViewModelTests+AttachmentLifecycle.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 01/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Observation
import XCTest
@testable import openclient_llm

@MainActor
extension ChatViewModelTests {
    func test_send_conversationChange_detachesSuspendedPhotoLoader() async throws {
        try await assertSuspendedPhotoIsDetached { model in
            model.send(.conversationLoaded(Conversation(modelId: "chat")))
        }
    }

    func test_send_viewDisappeared_detachesSuspendedPhotoLoaderInSameConversation() async throws {
        try await assertSuspendedPhotoIsDetached { model in
            model.send(.viewDisappeared)
        }
    }

    func test_resetAfterAppDataReset_detachesSuspendedPhotoLoader() async throws {
        mockFetchModels.result = .success([LLMModel(id: "chat")])
        try await assertSuspendedPhotoIsDetached { model in
            model.resetAfterAppDataReset()
        }
    }

    func test_send_lateCancelledPhoto_doesNotFinishActivePreparation() async throws {
        // Given
        sut.state = .loaded(.init(selectedModel: LLMModel(id: "chat")))
        let old = PhotoLoadGate(started: expectation(description: "Old load"))
        let current = PhotoLoadGate(started: expectation(description: "Current load"))
        defer { old.release(); current.release() }
        sut.send(.imagesSelected([old.input("old.png")]))
        await fulfillment(of: [old.started], timeout: 2)
        let oldTask = try XCTUnwrap(sut.attachmentPreparationTask)
        sut.send(.conversationLoaded(Conversation(modelId: "chat")))
        sut.send(.imagesSelected([current.input("current.png")]))
        await fulfillment(of: [current.started], timeout: 2)
        let currentTask = try XCTUnwrap(sut.attachmentPreparationTask)

        // When
        old.release()
        await waitForAttachmentTask(oldTask)

        // Then
        guard case .loaded(let waiting) = sut.state else { return XCTFail("Expected loaded state") }
        XCTAssertTrue(waiting.isPreparingAttachment)
        XCTAssertTrue(waiting.pendingAttachments.isEmpty)
        current.release()
        await waitForAttachmentTask(currentTask)
        guard case .loaded(let state) = sut.state else { return XCTFail("Expected loaded state") }
        XCTAssertEqual(state.pendingAttachments.map(\.fileName), ["current.png"])
        XCTAssertFalse(state.isPreparingAttachment)
    }

    func test_send_suspendedPhoto_doesNotRetainViewModel() async throws {
        // Given
        sut.state = .loaded(.init(selectedModel: LLMModel(id: "chat")))
        let gate = PhotoLoadGate(started: expectation(description: "Photo loading"))
        defer { gate.release() }
        sut.send(.imagesSelected([gate.input("photo.png")]))
        await fulfillment(of: [gate.started], timeout: 2)
        let task = try XCTUnwrap(sut.attachmentPreparationTask)
        let viewModelWasReleased = { [weak viewModel = sut] in viewModel == nil }

        // When
        sut = nil

        // Then
        XCTAssertTrue(viewModelWasReleased())
        gate.release()
        await waitForAttachmentTask(task)
    }

    private func assertSuspendedPhotoIsDetached(abandon: (ChatViewModel) -> Void) async throws {
        // Given
        sut.state = .loaded(.init(selectedModel: LLMModel(id: "chat")))
        let old = PhotoLoadGate(started: expectation(description: "Old photo loading"))
        defer { old.release() }
        sut.send(.imagesSelected([old.input("old.png")]))
        await fulfillment(of: [old.started], timeout: 2)
        let oldTask = try XCTUnwrap(sut.attachmentPreparationTask)

        // When
        abandon(sut)
        if case .loading = sut.state {
            let loaded = expectation(description: "Reload completed")
            withObservationTracking { _ = sut.state } onChange: { loaded.fulfill() }
            await fulfillment(of: [loaded], timeout: 2)
        }
        sut.send(.imagesSelected([.init(fileName: "new.png", loadData: { Data([2]) })]))
        let currentTask = try XCTUnwrap(sut.attachmentPreparationTask)
        let finished = expectation(description: "New photo finishes while old loader stays suspended")
        let observer = Task { await currentTask.value; finished.fulfill() }
        defer { observer.cancel() }
        await fulfillment(of: [finished], timeout: 2)

        // Then
        guard case .loaded(let ready) = sut.state else { return XCTFail("Expected loaded state") }
        XCTAssertFalse(ready.isPreparingAttachment)
        XCTAssertEqual(ready.pendingAttachments.map(\.fileName), ["new.png"])
        sut.send(.inputChanged("New image"))
        sut.send(.sendTapped)
        let sendTask = try XCTUnwrap(sut.streamTask)
        await waitForAttachmentTask(sendTask)
        guard case .loaded(let sent) = sut.state else { return XCTFail("Expected loaded state") }
        XCTAssertEqual(sent.messages.last(where: { $0.role == .user })?.attachments.count, 1)
        old.release()
        await waitForAttachmentTask(oldTask)
        guard case .loaded(let final) = sut.state else { return XCTFail("Expected loaded state") }
        XCTAssertEqual(final.messages, sent.messages)
        XCTAssertTrue(final.pendingAttachments.isEmpty)
        XCTAssertFalse(final.isPreparingAttachment)
    }
    func waitForAttachmentTask(_ task: Task<Void, Never>) async {
        let finished = expectation(description: "Attachment task completed")
        let observer = Task { await task.value; finished.fulfill() }
        defer { task.cancel(); observer.cancel() }
        await fulfillment(of: [finished], timeout: 2)
    }
}
