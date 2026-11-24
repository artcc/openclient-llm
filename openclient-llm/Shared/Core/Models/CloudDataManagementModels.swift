//
//  CloudDataManagementModels.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 11/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

nonisolated struct CloudPurgeMarker: Codable, Equatable, Sendable {
    let id: UUID
    let deletedAt: Date
}

nonisolated enum CloudPurgeCategoryState: String, Codable, Equatable, Sendable {
    case pending
    case cloudCleanupCompleted
    case completed
}

nonisolated struct CloudPurgeJournal: Codable, Equatable, Sendable {
    let marker: CloudPurgeMarker
    var categoryStates: [CloudDataCategory: CloudPurgeCategoryState]

    var unfinishedCategories: Set<CloudDataCategory> {
        Set(CloudDataCategory.allCases.filter { categoryStates[$0] != .completed })
    }
}

nonisolated enum CloudDataCategory: String, CaseIterable, Codable, Hashable, Sendable {
    case conversations
    case profile
    case memory
    case promptTemplates
}

nonisolated enum CloudInventoryFailure: String, Codable, Equatable, Sendable {
    case unavailable
    case pendingDownload
    case unsupportedSchema
    case corruptData
    case fileAccess
}

nonisolated struct CloudConversationInventoryItem: Equatable, Sendable {
    let id: UUID
    let title: String
    let updatedAt: Date
    let attachmentCount: Int
}

nonisolated struct CloudMemoryInventoryItem: Equatable, Sendable {
    let id: UUID
    let content: String
    let updatedAt: Date
}

nonisolated struct CloudPromptTemplateInventoryItem: Equatable, Sendable {
    let id: UUID
    let title: String
    let updatedAt: Date
}

nonisolated enum CloudInventoryCategoryValue: Equatable, Sendable {
    case conversations([CloudConversationInventoryItem], folderCount: Int = 0)
    case profileCount(Int)
    case memory([CloudMemoryInventoryItem])
    case promptTemplates([CloudPromptTemplateInventoryItem])
}

nonisolated enum CloudInventoryCategoryResult: Equatable, Sendable {
    case available(CloudInventoryCategoryValue)
    case failed(CloudInventoryFailure)
}

nonisolated struct CloudDataInventory: Equatable, Sendable {
    let categories: [CloudDataCategory: CloudInventoryCategoryResult]
}

nonisolated enum CloudDeletionCategoryOutcome: Equatable, Sendable {
    case deleted
    case failed(CloudInventoryFailure)
}

nonisolated struct CloudDeletionResult: Equatable, Sendable {
    let marker: CloudPurgeMarker
    let outcomes: [CloudDataCategory: CloudDeletionCategoryOutcome]

    var failedCategories: Set<CloudDataCategory> {
        Set(outcomes.compactMap { category, outcome in
            if case .failed = outcome { return category }
            return nil
        })
    }
}

nonisolated enum CloudDataManagementError: LocalizedError, Equatable, Sendable {
    case cloudSyncDisabled

    var errorDescription: String? {
        switch self {
        case .cloudSyncDisabled:
            String(localized: "Turn on iCloud synchronization before deleting synchronized data.")
        }
    }
}
