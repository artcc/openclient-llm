//
//  SaveServerConfigurationUseCase.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

protocol SaveServerConfigurationUseCaseProtocol: Sendable {
    @discardableResult func execute(
        serverURL: String, apiKey: String, customHeaders: [ServerHTTPHeader]?
    ) -> Bool
    @discardableResult func execute(
        serverURL: String, apiKey: String, customHeaders: [ServerHTTPHeader]?, chatIDHeaderName: String?
    ) -> Bool
}

extension SaveServerConfigurationUseCaseProtocol {
    @discardableResult
    func execute(serverURL: String, apiKey: String) -> Bool {
        execute(serverURL: serverURL, apiKey: apiKey, customHeaders: nil)
    }
}

struct SaveServerConfigurationUseCase: SaveServerConfigurationUseCaseProtocol {
    // MARK: - Properties

    private let settingsManager: SettingsManagerProtocol

    // MARK: - Init

    init(settingsManager: SettingsManagerProtocol = SettingsManager()) {
        self.settingsManager = settingsManager
    }

    // MARK: - Execute

    @discardableResult
    func execute(serverURL: String, apiKey: String, customHeaders: [ServerHTTPHeader]?) -> Bool {
        execute(
            serverURL: serverURL, apiKey: apiKey,
            customHeaders: customHeaders, chatIDHeaderName: settingsManager.getChatIDHeaderName()
        )
    }

    @discardableResult
    func execute(
        serverURL: String, apiKey: String, customHeaders: [ServerHTTPHeader]?, chatIDHeaderName: String?
    ) -> Bool {
        settingsManager.setServerConfiguration(
            serverBaseURL: serverURL, apiKey: apiKey,
            customHeaders: customHeaders ?? settingsManager.getCustomHeaders(), chatIDHeaderName: chatIDHeaderName
        )
    }
}
