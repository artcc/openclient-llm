//
//  MockTranscribeAudioUseCase.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 31/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation
@testable import openclient_llm

@MainActor
final class MockTranscribeAudioUseCase: TranscribeAudioUseCaseProtocol {
    // MARK: - Properties

    var result: Result<String, Error> = .success("Transcribed text")
    var executeCalled = false
    var executeCallCount = 0
    var executeHandler: (() async throws -> String)?

    // MARK: - Execute

    func execute(audioData: Data, model: String, language: String?, fileName: String) async throws -> String {
        executeCalled = true
        executeCallCount += 1
        if let executeHandler { return try await executeHandler() }
        return try result.get()
    }
}
