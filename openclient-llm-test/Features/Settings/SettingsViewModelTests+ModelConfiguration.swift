//
//  SettingsViewModelTests+ModelConfiguration.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 21/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

extension SettingsViewModelTests {
    func test_viewAppeared_loadsGlobalModelConfiguration() {
        let configuration = ChatModelConfiguration(parameters: ModelParameters(maxTokens: 4096))
        mockSettingsManager.globalChatModelConfiguration = configuration

        sut.send(.viewAppeared)

        guard case .loaded(let state) = sut.state else { return XCTFail("Expected loaded state") }
        XCTAssertEqual(state.modelConfiguration, configuration)
    }

    func test_modelConfigurationChanged_savesWholeBlockAndReset() {
        sut.send(.viewAppeared)
        let configuration = ChatModelConfiguration(
            parameters: ModelParameters(temperature: 0.5, maxTokens: 4096, topP: 0.9), contextWindowTokens: 8192
        )

        sut.send(.modelConfigurationChanged(configuration))

        guard case .loaded(let state) = sut.state else { return XCTFail("Expected loaded state") }
        XCTAssertEqual(state.modelConfiguration, configuration)
        XCTAssertEqual(mockSettingsManager.globalChatModelConfiguration, configuration)

        sut.send(.modelConfigurationChanged(.default))

        guard case .loaded(let resetState) = sut.state else { return XCTFail("Expected loaded state") }
        XCTAssertEqual(resetState.modelConfiguration, .default)
        XCTAssertEqual(mockSettingsManager.globalChatModelConfiguration, .default)
    }
}
