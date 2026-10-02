//
//  ChatViewModelTests+DropContext.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 01/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Observation
import UniformTypeIdentifiers
import XCTest
@testable import openclient_llm

@MainActor
extension ChatViewModelTests {
    func test_send_dropProviderPendingDuringConversationChange_discardsOldBytes() async throws {
        try await assertDropIsScoped { model in
            model.send(.conversationLoaded(Conversation(modelId: "chat")))
        }
    }

    func test_resetAfterAppDataReset_pendingDropProvider_discardsOldBytes() async throws {
        mockFetchModels.result = .success([LLMModel(id: "chat")])
        try await assertDropIsScoped { $0.resetAfterAppDataReset() }
    }

    private func assertDropIsScoped(abandon: (ChatViewModel) -> Void) async throws {
        // Given
        sut.state = .loaded(.init(inputText: "Old draft", selectedModel: LLMModel(id: "chat")))
        let gate = DropDataGate(started: expectation(description: "Provider loading"))
        defer { gate.release() }
        let provider = NSItemProvider()
        provider.suggestedName = "old.png"
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
            Task { @MainActor in gate.receive(completion) }
            return nil
        }
        sut.send(.itemsDropped(ChatDropModifier.inputs(from: [provider])))
        let oldTask = try XCTUnwrap(sut.attachmentPreparationTask)
        defer { oldTask.cancel() }
        await fulfillment(of: [gate.started], timeout: 2)
        sut.send(.sendTapped)
        guard case .loaded(let waiting) = sut.state else { return XCTFail("Expected loaded state") }
        XCTAssertTrue(waiting.isPreparingAttachment)
        XCTAssertTrue(waiting.messages.isEmpty)

        // When
        abandon(sut)
        if case .loading = sut.state {
            let loaded = expectation(description: "Data reloaded")
            withObservationTracking { _ = sut.state } onChange: { loaded.fulfill() }
            await fulfillment(of: [loaded], timeout: 2)
        }
        sut.send(.inputChanged("Current draft"))
        sut.send(.imagesSelected([.init(fileName: "new.png", loadData: { Data([2]) })]))
        await waitForAttachmentTask(try XCTUnwrap(sut.attachmentPreparationTask))
        guard case .loaded(let before) = sut.state else { return XCTFail("Expected loaded state") }
        gate.release()
        await waitForAttachmentTask(oldTask)

        // Then
        guard case .loaded(let after) = sut.state else { return XCTFail("Expected loaded state") }
        XCTAssertEqual(before.pendingAttachments.map(\.fileName), ["new.png"])
        XCTAssertFalse(before.isPreparingAttachment)
        XCTAssertEqual(after.pendingAttachments, before.pendingAttachments)
        XCTAssertEqual(after.inputText, "Current draft")
        XCTAssertFalse(after.isPreparingAttachment)
        XCTAssertNil(after.errorMessage)
    }
}

@MainActor
private final class DropDataGate {
    let started: XCTestExpectation
    private var callback: (@Sendable (Data?, (any Error)?) -> Void)?
    private var isReleased = false

    init(started: XCTestExpectation) { self.started = started }

    func receive(_ completion: @escaping @Sendable (Data?, (any Error)?) -> Void) {
        started.fulfill()
        if isReleased {
            completion(Data([1]), nil)
        } else {
            callback = completion
        }
    }

    func release() {
        isReleased = true
        let completion = callback
        callback = nil
        completion?(Data([1]), nil)
    }
}
