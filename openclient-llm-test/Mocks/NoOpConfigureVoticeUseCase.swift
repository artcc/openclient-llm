//
//  NoOpConfigureVoticeUseCase.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 24/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

@testable import openclient_llm

struct NoOpConfigureVoticeUseCase: ConfigureVoticeUseCaseProtocol {
    func execute(userIsPremium: Bool) {}
}
