//
//  ConversationListView+Backup.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 13/07/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

extension ConversationListView {
    // MARK: - Backup

    var backupData: Data? {
        guard case .loaded(let loadedState) = viewModel.state else { return nil }
        return loadedState.backupData
    }

    var importResult: ImportConversationsResult? {
        guard case .loaded(let loadedState) = viewModel.state else { return nil }
        return loadedState.importResult
    }

    var errorMessage: String? {
        guard case .loaded(let loadedState) = viewModel.state else { return nil }
        return loadedState.errorMessage
    }

    var importResultMessage: String {
        guard let importResult else { return "" }
        let conversationCount = importResult.importedConversationCount
        let restoredAttachmentCount = importResult.restoredAttachmentCount
        let skippedAttachmentCount = importResult.skippedAttachmentCount
        let folderSummary = importResult.importedFolderCount > 0
            ? "\n" + String(localized: "Folders imported: \(importResult.importedFolderCount)") : ""
        guard skippedAttachmentCount > 0 else {
            let format = String(
                localized: "Imported %lld conversations and restored %lld attachments."
            )
            return String.localizedStringWithFormat(format, conversationCount, restoredAttachmentCount) + folderSummary
        }
        let format = String(
            localized: "Imported %lld conversations, restored %lld attachments, and skipped %lld attachments."
        )
        return String.localizedStringWithFormat(
            format,
            conversationCount,
            restoredAttachmentCount,
            skippedAttachmentCount
        ) + folderSummary
    }

    func importBackup(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure(let error) = result, !isUserCancellation(error) {
                viewModel.send(.backupImportReadFailed)
            }
            return
        }
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { url.stopAccessingSecurityScopedResource() }
        }
        guard let data = try? Data(contentsOf: url) else {
            viewModel.send(.backupImportReadFailed)
            return
        }
        viewModel.send(.importBackupData(data))
    }

    func isUserCancellation(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError
    }

}
