//
//  MarkdownFootnote.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 13/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

nonisolated struct MarkdownFootnote: Equatable, Sendable {
    let number: Int
    let label: String
    let content: String
}
