//
//  ConversationCreationPlacement.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 23/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

/// Resolved by storage only when inserting a new conversation.
nonisolated enum ConversationCreationPlacement: Equatable, Sendable {
    case folder(UUID)
    case inheritFrom(UUID)
}
