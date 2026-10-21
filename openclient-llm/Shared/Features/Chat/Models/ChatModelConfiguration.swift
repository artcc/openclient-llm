//
//  ChatModelConfiguration.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 21/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

nonisolated struct ChatModelConfiguration: Codable, Equatable, Sendable {
    var parameters: ModelParameters = .default
    var contextWindowTokens: Int?

    static let `default` = ChatModelConfiguration()

    var hasCustomValues: Bool {
        parameters.hasCustomValues || contextWindowTokens != nil
    }
}
