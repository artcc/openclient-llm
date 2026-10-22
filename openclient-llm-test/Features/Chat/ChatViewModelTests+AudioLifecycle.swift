//
//  ChatViewModelTests+AudioLifecycle.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 21/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
extension ChatViewModelTests {
    func test_send_cancelPendingPermission_ignoresLateSuccess() async throws {
        let recorder = MockRecordAudioUseCase()
        let requested = expectation(description: "Permission requested")
        var permission: CheckedContinuation<Void, Never>?
        recorder.startRecordingHandler = {
            await withCheckedContinuation {
                permission = $0
                requested.fulfill()
            }
        }
        sut = makeAudioViewModel(recorder: recorder)
        sut.send(.startRecordingTapped)
        let startTask = sut.recordingStartTask
        await fulfillment(of: [requested], timeout: 2)

        sut.send(.cancelRecordingTapped)
        permission?.resume()
        await startTask?.value

        XCTAssertFalse(try audioState().isStartingRecording)
        XCTAssertFalse(try audioState().isRecording)
        XCTAssertNil(try audioState().errorMessage)
        XCTAssertNil(sut.durationTrackingTask)
    }

    func test_send_stopDuringPermission_cancelsWithoutTranscription() async throws {
        let recorder = MockRecordAudioUseCase()
        sut = makeAudioViewModel(recorder: recorder)
        sut.send(.startRecordingTapped)
        let startTask = sut.recordingStartTask

        sut.send(.stopRecordingTapped)
        await startTask?.value

        XCTAssertFalse(try audioState().isStartingRecording)
        XCTAssertFalse(try audioState().isRecording)
        XCTAssertFalse(recorder.stopRecordingCalled)
        XCTAssertNil(sut.transcriptionTask)
    }

    func test_send_leaveOrChangeConversation_stopsRecording() async throws {
        let events: [ChatViewModel.Event] = [.viewDisappeared, .conversationLoaded(Conversation(modelId: "other"))]
        for event in events {
            let recorder = MockRecordAudioUseCase()
            sut = makeAudioViewModel(recorder: recorder)
            sut.send(.startRecordingTapped)
            await sut.recordingStartTask?.value

            sut.send(event)

            XCTAssertTrue(recorder.cancelRecordingCalled)
            XCTAssertFalse(try audioState().isRecording)
            XCTAssertNil(sut.durationTrackingTask)
        }
    }

    func test_send_lateTranscriptionAfterConversationChange_doesNotOverwriteNewDraft() async throws {
        let transcriber = MockTranscribeAudioUseCase()
        let requested = expectation(description: "Transcription requested")
        var response: CheckedContinuation<String, Never>?
        transcriber.executeHandler = {
            await withCheckedContinuation {
                response = $0
                requested.fulfill()
            }
        }
        let recorder = MockRecordAudioUseCase()
        recorder.stopRecordingResult = (Data([1]), 2)
        sut = makeAudioViewModel(recorder: recorder, transcriber: transcriber)
        sut.send(.startRecordingTapped)
        await sut.recordingStartTask?.value
        sut.send(.stopRecordingTapped)
        let transcriptionTask = sut.transcriptionTask
        await fulfillment(of: [requested], timeout: 2)

        sut.send(.conversationLoaded(Conversation(modelId: "other")))
        sut.send(.inputChanged("New draft"))
        response?.resume(returning: "Old conversation audio")
        await transcriptionTask?.value

        XCTAssertEqual(try audioState().inputText, "New draft")
        XCTAssertFalse(try audioState().isTranscribing)
        XCTAssertNil(try audioState().errorMessage)
    }

    func test_send_draftEditedDuringTranscription_preservesEdits() async throws {
        let recorder = MockRecordAudioUseCase()
        recorder.stopRecordingResult = (Data([1]), 2)
        sut = makeAudioViewModel(recorder: recorder)
        sut.send(.startRecordingTapped)
        await sut.recordingStartTask?.value
        sut.send(.stopRecordingTapped)

        sut.send(.inputChanged("Keep my edits"))
        await sut.transcriptionTask?.value

        XCTAssertEqual(try audioState().inputText, "Keep my edits")
        XCTAssertFalse(try audioState().isTranscribing)
        XCTAssertNotNil(try audioState().errorMessage)
    }

    func test_send_lateTranscriptionFailure_doesNotAffectNewRecording() async throws {
        let transcriber = MockTranscribeAudioUseCase()
        let requested = expectation(description: "Transcription requested")
        var response: CheckedContinuation<String, any Error>?
        transcriber.executeHandler = {
            try await withCheckedThrowingContinuation {
                response = $0
                requested.fulfill()
            }
        }
        let recorder = MockRecordAudioUseCase()
        recorder.stopRecordingResult = (Data([1]), 2)
        sut = makeAudioViewModel(recorder: recorder, transcriber: transcriber)
        sut.send(.startRecordingTapped)
        await sut.recordingStartTask?.value
        sut.send(.stopRecordingTapped)
        let oldTask = sut.transcriptionTask
        await fulfillment(of: [requested], timeout: 2)

        sut.send(.cancelRecordingTapped)
        sut.send(.startRecordingTapped)
        await sut.recordingStartTask?.value
        response?.resume(throwing: APIError.serverUnreachable)
        await oldTask?.value

        XCTAssertTrue(try audioState().isRecording)
        XCTAssertNil(try audioState().errorMessage)
        XCTAssertTrue(recorder.isRecording)
        sut.send(.cancelRecordingTapped)
    }

    func test_deinit_activeRecording_doesNotRetainViewModelAndStopsCapture() async {
        let recorder = MockRecordAudioUseCase()
        sut = makeAudioViewModel(recorder: recorder)
        sut.send(.startRecordingTapped)
        await sut.recordingStartTask?.value
        let isViewModelReleased = { [weak viewModel = sut] in viewModel == nil }

        sut = nil

        XCTAssertTrue(isViewModelReleased())
        XCTAssertFalse(recorder.isRecording)
        XCTAssertTrue(recorder.cancelRecordingCalled)
    }

    func test_send_audioInProgress_blocksSendingAndHandoff() throws {
        let states = [
            ChatViewModel.LoadedState(isRecording: true),
            ChatViewModel.LoadedState(isStartingRecording: true),
            ChatViewModel.LoadedState(isTranscribing: true)
        ]
        for var state in states {
            state.inputText = "Draft"
            state.selectedModel = LLMModel(id: "gpt-4")
            sut.state = .loaded(state)

            sut.send(.sendTapped)

            XCTAssertEqual(try audioState().inputText, "Draft")
            XCTAssertTrue(try audioState().messages.isEmpty)
            XCTAssertFalse(sut.canPrepareForAppHandoff)
        }
    }

    func test_deinit_pendingPermission_doesNotRetainViewModel() async {
        let recorder = MockRecordAudioUseCase()
        let requested = expectation(description: "Permission requested")
        var permission: CheckedContinuation<Void, Never>?
        recorder.startRecordingHandler = {
            await withCheckedContinuation {
                permission = $0
                requested.fulfill()
            }
        }
        sut = makeAudioViewModel(recorder: recorder)
        let isViewModelReleased = { [weak viewModel = sut] in viewModel == nil }
        sut.send(.startRecordingTapped)
        let task = sut.recordingStartTask
        await fulfillment(of: [requested], timeout: 2)

        sut = nil

        XCTAssertTrue(isViewModelReleased())
        XCTAssertTrue(recorder.cancelRecordingCalled)
        permission?.resume()
        await task?.value
    }
}
