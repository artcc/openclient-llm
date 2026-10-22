//
//  ChatViewModelTests+Transcription.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 01/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
extension ChatViewModelTests {
    func test_send_startRecordingTapped_setsIsRecordingOnlyAfterSuccess() async throws {
        let recorder = MockRecordAudioUseCase()
        sut = makeAudioViewModel(recorder: recorder)

        sut.send(.startRecordingTapped)
        XCTAssertTrue(try audioState().isStartingRecording)
        XCTAssertFalse(try audioState().isRecording)
        await sut.recordingStartTask?.value

        XCTAssertTrue(try audioState().isRecording)
        XCTAssertFalse(try audioState().isStartingRecording)
        XCTAssertEqual(recorder.startRecordingCallCount, 1)
        sut.send(.cancelRecordingTapped)
    }

    func test_send_startRecordingFails_keepsComposerIdleAndShowsError() async throws {
        for error in [AudioRecordingError.permissionDenied, .startFailed] {
            let recorder = MockRecordAudioUseCase()
            recorder.startRecordingError = error
            sut = makeAudioViewModel(recorder: recorder)

            sut.send(.startRecordingTapped)
            await sut.recordingStartTask?.value

            let state = try audioState()
            XCTAssertFalse(state.isRecording)
            XCTAssertFalse(state.isStartingRecording)
            XCTAssertEqual(state.recordingDuration, 0)
            XCTAssertEqual(state.errorMessage, error.localizedDescription)
            XCTAssertNil(sut.durationTrackingTask)
            XCTAssertTrue(recorder.cancelRecordingCalled)
        }
    }

    func test_send_duplicateStart_doesNotRestartRecorder() async throws {
        let recorder = MockRecordAudioUseCase()
        sut = makeAudioViewModel(recorder: recorder)

        sut.send(.startRecordingTapped)
        sut.send(.startRecordingTapped)
        await sut.recordingStartTask?.value
        sut.send(.startRecordingTapped)

        XCTAssertEqual(recorder.startRecordingCallCount, 1)
        XCTAssertTrue(try audioState().isRecording)
        sut.send(.cancelRecordingTapped)
    }

    func test_send_cancelRecordingTapped_clearsRecording() async throws {
        let recorder = MockRecordAudioUseCase()
        sut = makeAudioViewModel(recorder: recorder)
        sut.send(.startRecordingTapped)
        await sut.recordingStartTask?.value

        sut.send(.cancelRecordingTapped)

        XCTAssertFalse(try audioState().isRecording)
        XCTAssertTrue(recorder.cancelRecordingCalled)
        XCTAssertNil(sut.durationTrackingTask)
    }

    func test_send_stopRecordingTapped_transcribesOnceAndUpdatesDraft() async throws {
        let recorder = MockRecordAudioUseCase()
        recorder.stopRecordingResult = (Data([1, 2, 3]), 2)
        let transcriber = MockTranscribeAudioUseCase()
        transcriber.result = .success("Hello world")
        sut = makeAudioViewModel(recorder: recorder, transcriber: transcriber)
        sut.send(.startRecordingTapped)
        await sut.recordingStartTask?.value

        sut.send(.stopRecordingTapped)
        sut.send(.stopRecordingTapped)
        await sut.transcriptionTask?.value

        XCTAssertTrue(recorder.stopRecordingCalled)
        XCTAssertEqual(transcriber.executeCallCount, 1)
        let state = try audioState()
        XCTAssertFalse(state.isRecording)
        XCTAssertFalse(state.isTranscribing)
        XCTAssertEqual(state.inputText, "Hello world")
        XCTAssertEqual(state.inputRevision, 1)
    }

    func test_send_stopRecordingTapped_withoutRecording_doesNotTranscribe() {
        let recorder = MockRecordAudioUseCase()
        let transcriber = MockTranscribeAudioUseCase()
        sut = makeAudioViewModel(recorder: recorder, transcriber: transcriber)

        sut.send(.stopRecordingTapped)

        XCTAssertFalse(recorder.stopRecordingCalled)
        XCTAssertFalse(transcriber.executeCalled)
    }

    func test_send_shortRecording_doesNotTranscribe() async throws {
        let recorder = MockRecordAudioUseCase()
        recorder.stopRecordingResult = (Data([1]), 0.2)
        let transcriber = MockTranscribeAudioUseCase()
        sut = makeAudioViewModel(recorder: recorder, transcriber: transcriber)
        sut.send(.startRecordingTapped)
        await sut.recordingStartTask?.value

        sut.send(.stopRecordingTapped)

        XCTAssertFalse(transcriber.executeCalled)
        XCTAssertFalse(try audioState().isTranscribing)
        XCTAssertNil(try audioState().errorMessage)
    }

    func test_send_stopFailure_cleansUpAndShowsError() async throws {
        let recorder = MockRecordAudioUseCase()
        recorder.stopRecordingError = AudioRecordingError.readFailed
        sut = makeAudioViewModel(recorder: recorder)
        sut.send(.startRecordingTapped)
        await sut.recordingStartTask?.value

        sut.send(.stopRecordingTapped)

        XCTAssertTrue(recorder.cancelRecordingCalled)
        XCTAssertFalse(try audioState().isRecording)
        XCTAssertEqual(try audioState().errorMessage, AudioRecordingError.readFailed.localizedDescription)
        XCTAssertNil(sut.durationTrackingTask)
    }

    func test_send_recordingWithoutData_reportsFailureWithoutTranscription() async throws {
        let recorder = MockRecordAudioUseCase()
        let transcriber = MockTranscribeAudioUseCase()
        sut = makeAudioViewModel(recorder: recorder, transcriber: transcriber)
        sut.send(.startRecordingTapped)
        await sut.recordingStartTask?.value

        sut.send(.stopRecordingTapped)

        XCTAssertFalse(transcriber.executeCalled)
        XCTAssertFalse(try audioState().isRecording)
        XCTAssertEqual(try audioState().errorMessage, AudioRecordingError.readFailed.localizedDescription)
    }

    func test_send_transcriptionFails_preservesDraftAndShowsError() async throws {
        let recorder = MockRecordAudioUseCase()
        recorder.stopRecordingResult = (Data([1]), 2)
        let transcriber = MockTranscribeAudioUseCase()
        transcriber.result = .failure(APIError.serverUnreachable)
        sut = makeAudioViewModel(recorder: recorder, transcriber: transcriber)
        sut.send(.startRecordingTapped)
        await sut.recordingStartTask?.value

        sut.send(.stopRecordingTapped)
        await sut.transcriptionTask?.value

        XCTAssertFalse(try audioState().isTranscribing)
        XCTAssertNotNil(try audioState().errorMessage)
        XCTAssertEqual(try audioState().inputText, "")
    }

    func test_refreshRecordingState_usesRecorderDurationAndDetectsInterruption() async throws {
        let recorder = MockRecordAudioUseCase()
        sut = makeAudioViewModel(recorder: recorder)
        sut.send(.startRecordingTapped)
        await sut.recordingStartTask?.value
        recorder.recordingDuration = 1.25

        sut.refreshRecordingState()
        XCTAssertEqual(try audioState().recordingDuration, 1.25)
        recorder.isRecording = false
        sut.refreshRecordingState()

        XCTAssertFalse(try audioState().isRecording)
        XCTAssertEqual(try audioState().recordingDuration, 0)
        XCTAssertEqual(try audioState().errorMessage, AudioRecordingError.interrupted.localizedDescription)
        XCTAssertNil(sut.durationTrackingTask)
    }

    func test_makeLoadedState_noServerTranscriptionModels_usesAppleSpeech() {
        sut = makeAudioViewModel()
        let state = sut.makeLoadedState(models: [LLMModel(id: "gpt-4")], pending: nil)
        XCTAssertEqual(state.transcriptionModelId, LLMModel.appleSpeechRecognition.id)
    }

    // MARK: - Helpers

    func audioState() throws -> ChatViewModel.LoadedState {
        try XCTUnwrap({
            if case .loaded(let state) = sut.state { return state }
            return nil
        }(), "Expected loaded state")
    }

    func makeAudioViewModel(
        recorder: MockRecordAudioUseCase = MockRecordAudioUseCase(),
        transcriber: MockTranscribeAudioUseCase = MockTranscribeAudioUseCase()
    ) -> ChatViewModel {
        ChatViewModel(
            isPrivateChat: true,
            state: .loaded(.init(selectedModel: LLMModel(id: "gpt-4"), transcriptionModelId: "whisper-1")),
            fetchModelsUseCase: mockFetchModels,
            streamMessageUseCase: mockStreamMessage,
            saveConversationUseCase: mockSaveConversation,
            transcribeAudioUseCase: transcriber,
            getChatPreferencesUseCase: mockGetChatPreferences,
            fetchMCPToolsUseCase: mockFetchMCPTools,
            settingsManager: MockSettingsManager(),
            resolveAudioModelIdsUseCase: ResolveAudioModelIdsUseCase(settingsManager: MockSettingsManager()),
            getConversationStartersUseCase: mockGetConversationStarters,
            recordAudioUseCase: recorder,
            triggerHapticFeedbackUseCase: MockTriggerHapticFeedbackUseCase()
        )
    }
}
