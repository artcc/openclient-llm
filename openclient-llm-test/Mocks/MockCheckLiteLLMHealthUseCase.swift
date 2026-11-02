//
//  MockCheckLiteLLMHealthUseCase.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 08/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation
@testable import openclient_llm

// Safety: Only used within serialized @MainActor test methods.
final class MockCheckLiteLLMHealthUseCase: CheckLiteLLMHealthUseCaseProtocol, @unchecked Sendable {
    // MARK: - Properties

    var result: Bool = true

    // MARK: - Execute

    func execute(serverURL: String, customHeaders: [ServerHTTPHeader]) async -> Bool {
        result
    }
}
