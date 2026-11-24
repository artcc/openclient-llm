//
//  MockResetAppDataUseCase.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation
@testable import openclient_llm

@MainActor
final class MockResetAppDataUseCase: ResetAppDataUseCaseProtocol {
    // MARK: - Properties

    private(set) var executeCallCount = 0
    var executeCalled: Bool { executeCallCount > 0 }
    var executeError: Error?
    var onExecute: (@MainActor () async throws -> Void)?

    // MARK: - Execute

    func execute() async throws {
        executeCallCount += 1
        if let executeError { throw executeError }
        try await onExecute?()
    }
}
