//
//  AudioRecordingSession.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 21/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import AVFoundation
import Foundation

@MainActor
protocol AudioRecordingSessionProtocol: AnyObject {
    var isRecording: Bool { get }
    var currentTime: TimeInterval { get }

    func requestPermission() async -> Bool
    func record(to url: URL) throws -> Bool
    func stop()
}

@MainActor
final class AudioRecordingSession: AudioRecordingSessionProtocol {
    private var recorder: AVAudioRecorder?
    #if os(iOS)
    private var ownsAudioSession = false
    #endif

    var isRecording: Bool { recorder?.isRecording ?? false }
    var currentTime: TimeInterval { recorder?.currentTime ?? 0 }

    func requestPermission() async -> Bool {
        #if os(iOS)
        return await AVAudioApplication.requestRecordPermission()
        #else
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
        #endif
    }

    func record(to url: URL) throws -> Bool {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
        ownsAudioSession = true
        #endif

        recorder = try AVAudioRecorder(url: url, settings: [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ])
        return recorder?.record() == true
    }

    func stop() {
        recorder?.stop()
        recorder = nil
        #if os(iOS)
        guard ownsAudioSession else { return }
        ownsAudioSession = false
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            LogManager.error("Failed to deactivate the recording audio session")
        }
        #endif
    }
}
