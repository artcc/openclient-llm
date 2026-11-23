//
//  ConversationStorage+SynchronizationModels.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 11/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

// MARK: - Synchronization Models

extension ConversationStorage {
    struct ConversationFiles {
        var values: [UUID: Conversation] = [:]
        var data: [UUID: Data] = [:]
    }

    struct MergedConversation {
        let conversation: Conversation
        let data: Data
        let source: Source
        let localInlineAttachmentData: [CloudAttachmentKey: Data]
        let cloudInlineAttachmentData: [CloudAttachmentKey: Data]
    }

    enum Source: Equatable {
        case local
        case cloud
        case equivalent
    }

    struct SynchronizationPlan {
        var output: ConversationCloudSyncOutput
        let mutatedConversation: Conversation?
        let resolvedPendingMutationIds: Set<UUID>
        let resolvedPendingDeletionIds: Set<UUID>
        let localAttachmentKeys: Set<CloudAttachmentKey>
        let localConflictAttachmentKeys: Set<CloudAttachmentKey>
    }
}
