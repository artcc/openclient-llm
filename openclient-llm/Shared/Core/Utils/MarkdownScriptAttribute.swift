//
//  MarkdownScriptAttribute.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 13/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

/// Semantic position: -1 for a subscript, 1 for a superscript. UI resolves the font metrics.
nonisolated enum MarkdownScriptAttribute: AttributedStringKey {
    typealias Value = Int
    static let name = "com.artcc.openclient.markdown.script"
}
