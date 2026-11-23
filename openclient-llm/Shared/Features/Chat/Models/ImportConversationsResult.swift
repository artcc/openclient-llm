//
//  ImportConversationsResult.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 13/07/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

struct ImportConversationsResult: Equatable, Sendable {
    // MARK: - Properties

    let importedConversationCount: Int
    let importedFolderCount: Int
    let restoredAttachmentCount: Int
    let skippedAttachmentCount: Int

    init(
        importedConversationCount: Int,
        importedFolderCount: Int = 0,
        restoredAttachmentCount: Int,
        skippedAttachmentCount: Int
    ) {
        self.importedConversationCount = importedConversationCount
        self.importedFolderCount = importedFolderCount
        self.restoredAttachmentCount = restoredAttachmentCount
        self.skippedAttachmentCount = skippedAttachmentCount
    }
}
