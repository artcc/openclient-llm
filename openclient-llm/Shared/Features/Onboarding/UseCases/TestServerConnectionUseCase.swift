//
//  TestServerConnectionUseCase.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

protocol TestServerConnectionUseCaseProtocol: Sendable {
    func execute(serverURL: String, apiKey: String, customHeaders: [ServerHTTPHeader]) async throws
}

extension TestServerConnectionUseCaseProtocol {
    func execute(serverURL: String, apiKey: String) async throws {
        try await execute(serverURL: serverURL, apiKey: apiKey, customHeaders: [])
    }
}

struct TestServerConnectionUseCase: TestServerConnectionUseCaseProtocol {
    // MARK: - Properties

    private let repository: OnboardingRepositoryProtocol

    // MARK: - Init

    init(repository: OnboardingRepositoryProtocol = OnboardingRepository()) {
        self.repository = repository
    }

    // MARK: - Execute

    func execute(serverURL: String, apiKey: String, customHeaders: [ServerHTTPHeader]) async throws {
        try await repository.testConnection(serverURL: serverURL, apiKey: apiKey, customHeaders: customHeaders)
    }
}
