//
//  ToolsViewModelTests.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 11/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class ToolsViewModelTests: XCTestCase {
    func test_send_viewAppeared_loadsSavedToolPreferences() {
        // Given
        let settings = MockSettingsManager()
        settings.disabledBuiltInTools = [.saveMemory, .generateImage]
        let sut = ToolsViewModel(settingsManager: settings)

        // When
        sut.send(.viewAppeared)

        // Then
        XCTAssertEqual(sut.state, .loaded(.init(
            enabledTools: Set(BuiltInTool.allCases).subtracting([.saveMemory, .generateImage])
        )))
    }

    func test_send_toolToggled_persistsOnlySelectedToolAndUpdatesState() {
        // Given
        let settings = MockSettingsManager()
        let sut = ToolsViewModel(settingsManager: settings)
        sut.send(.viewAppeared)

        // When
        sut.send(.toolToggled(.deleteMemory, enabled: false))

        // Then
        XCTAssertEqual(settings.disabledBuiltInTools, [.deleteMemory])
        XCTAssertEqual(sut.state, .loaded(.init(
            enabledTools: Set(BuiltInTool.allCases).subtracting([.deleteMemory])
        )))
    }

    func test_send_reenableTool_restoresSavedPreference() {
        // Given
        let settings = MockSettingsManager()
        settings.disabledBuiltInTools = [.currentDatetime]
        let sut = ToolsViewModel(settingsManager: settings)
        sut.send(.viewAppeared)

        // When
        sut.send(.toolToggled(.currentDatetime, enabled: true))
        let reopened = ToolsViewModel(settingsManager: settings)
        reopened.send(.viewAppeared)

        // Then
        XCTAssertTrue(settings.disabledBuiltInTools.isEmpty)
        XCTAssertEqual(reopened.state, .loaded(.init(enabledTools: Set(BuiltInTool.allCases))))
    }
}
