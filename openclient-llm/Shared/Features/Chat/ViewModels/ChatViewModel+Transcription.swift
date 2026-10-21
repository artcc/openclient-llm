//
//  ChatViewModel+Transcription.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 01/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

// MARK: - Audio Recording & Transcription

extension ChatViewModel {
    /// Minimum recording duration in seconds required to attempt transcription.
    private static let minimumRecordingDuration: TimeInterval = 0.3

    func startRecording() {
        guard case .loaded(var loadedState) = state,
              !loadedState.isStartingRecording, !loadedState.isRecording,
              !loadedState.isTranscribing, !loadedState.isStreaming,
              !loadedState.isPreparingAttachment,
              loadedState.selectedModel != nil, loadedState.transcriptionModelId != nil else { return }
        loadedState.isStartingRecording = true
        loadedState.errorMessage = nil
        state = .loaded(loadedState)
        let generation = audioGeneration
        let useCase = recordAudioUseCase
        recordingStartTask = Task { [weak self] in
            do {
                try await useCase.startRecording()
                guard !Task.isCancelled, let self, audioGeneration == generation else { return }
                recordingStartTask = nil
                guard case .loaded(var currentState) = state else {
                    cancelRecording()
                    return
                }
                currentState.isStartingRecording = false
                currentState.isRecording = true
                currentState.recordingDuration = 0
                state = .loaded(currentState)
                startDurationTracking()
            } catch {
                guard !Task.isCancelled, let self, audioGeneration == generation else { return }
                cancelRecording()
                if !(error is CancellationError) { showAudioError(error) }
            }
        }
    }

    func stopRecording() {
        guard case .loaded(var loadedState) = state else { return }
        if loadedState.isStartingRecording {
            cancelRecording()
            return
        }
        guard loadedState.isRecording else { return }
        durationTrackingTask?.cancel()
        durationTrackingTask = nil
        loadedState.isRecording = false
        loadedState.recordingDuration = 0
        state = .loaded(loadedState)
        do {
            let result = try recordAudioUseCase.stopRecording()
            guard let data = result.data else { throw AudioRecordingError.readFailed }
            transcribeAudio(data: data, duration: result.duration)
        } catch {
            recordAudioUseCase.cancelRecording()
            showAudioError(error)
        }
    }

    /// Invalidates the entire audio operation, including permission and transcription completions.
    func cancelRecording() {
        audioGeneration += 1
        recordingStartTask?.cancel()
        recordingStartTask = nil
        transcriptionTask?.cancel()
        transcriptionTask = nil
        durationTrackingTask?.cancel()
        durationTrackingTask = nil
        recordAudioUseCase.cancelRecording()
        guard case .loaded(var loadedState) = state else { return }
        loadedState.isStartingRecording = false
        loadedState.isRecording = false
        loadedState.recordingDuration = 0
        loadedState.isTranscribing = false
        state = .loaded(loadedState)
    }

    func transcribeAudio(data: Data, duration: TimeInterval) {
        guard case .loaded(var loadedState) = state, !loadedState.isTranscribing else { return }
        guard duration >= Self.minimumRecordingDuration, !data.isEmpty else { return }
        guard let modelId = loadedState.transcriptionModelId else {
            showAudioErrorMessage(String(localized: "No speech-to-text model is available."))
            return
        }
        loadedState.isTranscribing = true
        state = .loaded(loadedState)
        let generation = audioGeneration
        let inputText = loadedState.inputText
        let inputRevision = loadedState.inputRevision
        let useCase = transcribeAudioUseCase
        transcriptionTask = Task { [weak self] in
            do {
                let text = try await useCase.execute(
                    audioData: data, model: modelId, language: nil, fileName: "recording.m4a"
                )
                guard !Task.isCancelled, let self, audioGeneration == generation,
                      case .loaded(var currentState) = state else { return }
                transcriptionTask = nil
                currentState.isTranscribing = false
                guard currentState.inputText == inputText, currentState.inputRevision == inputRevision else {
                    state = .loaded(currentState)
                    showAudioErrorMessage(String(
                        localized: "The draft changed during transcription. Please record again."
                    ))
                    return
                }
                currentState.inputText = text
                currentState.inputRevision += 1
                state = .loaded(currentState)
                triggerHapticFeedbackUseCase.lightImpact()
            } catch {
                guard !Task.isCancelled, let self, audioGeneration == generation,
                      case .loaded(var currentState) = state else { return }
                transcriptionTask = nil
                currentState.isTranscribing = false
                state = .loaded(currentState)
                if !(error is CancellationError) {
                    let message = (error as? AppleSpeechError)?.localizedDescription
                        ?? String(localized: "Audio transcription failed. Please try again.")
                    showAudioErrorMessage(message)
                }
            }
        }
    }

    func handleRecordingEvent(_ event: Event) {
        switch event {
        case .startRecordingTapped: startRecording()
        case .stopRecordingTapped: stopRecording()
        case .cancelRecordingTapped: cancelRecording()
        default: break
        }
    }

    func refreshRecordingState() {
        guard case .loaded(var loadedState) = state, loadedState.isRecording else { return }
        guard recordAudioUseCase.isRecording else {
            cancelRecording()
            showAudioError(AudioRecordingError.interrupted)
            return
        }
        loadedState.recordingDuration = recordAudioUseCase.recordingDuration
        state = .loaded(loadedState)
    }
}

// MARK: - Private

private extension ChatViewModel {
    func startDurationTracking() {
        durationTrackingTask?.cancel()
        durationTrackingTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                guard !Task.isCancelled, let self else { return }
                refreshRecordingState()
            }
        }
    }

    func showAudioError(_ error: Error) {
        let recordingError = error as? AudioRecordingError ?? .startFailed
        showAudioErrorMessage(recordingError.localizedDescription)
    }

    func showAudioErrorMessage(_ message: String) {
        guard case .loaded(var loadedState) = state else { return }
        loadedState.errorMessage = message
        state = .loaded(loadedState)
        scheduleErrorDismiss()
    }
}
