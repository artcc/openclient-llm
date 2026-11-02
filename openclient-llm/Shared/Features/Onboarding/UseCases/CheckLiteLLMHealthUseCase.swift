//
//  CheckLiteLLMHealthUseCase.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 08/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

protocol CheckLiteLLMHealthUseCaseProtocol: Sendable {
    func execute(serverURL: String, customHeaders: [ServerHTTPHeader]) async -> Bool
}

extension CheckLiteLLMHealthUseCaseProtocol {
    func execute(serverURL: String) async -> Bool {
        await execute(serverURL: serverURL, customHeaders: [])
    }
}

struct CheckLiteLLMHealthUseCase: CheckLiteLLMHealthUseCaseProtocol {
    // MARK: - Properties

    private let repository: OnboardingRepositoryProtocol

    // MARK: - Init

    init(repository: OnboardingRepositoryProtocol = OnboardingRepository()) {
        self.repository = repository
    }

    // MARK: - Execute

    func execute(serverURL: String, customHeaders: [ServerHTTPHeader]) async -> Bool {
        await repository.checkLiteLLMHealth(serverURL: serverURL, customHeaders: customHeaders)
    }
}
