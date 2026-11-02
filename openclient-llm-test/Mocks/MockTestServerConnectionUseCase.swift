//
//  MockTestServerConnectionUseCase.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation
@testable import openclient_llm

// Safety: Only used within serialized @MainActor test methods.
final class MockTestServerConnectionUseCase: TestServerConnectionUseCaseProtocol, @unchecked Sendable {
    // MARK: - Properties

    var result: Result<Void, Error> = .success(())
    var testedCustomHeaders: [ServerHTTPHeader]?
    var onExecute: (() -> Void)?

    // MARK: - Execute

    func execute(serverURL: String, apiKey: String, customHeaders: [ServerHTTPHeader]) async throws {
        testedCustomHeaders = customHeaders
        onExecute?()
        try result.get()
    }
}
