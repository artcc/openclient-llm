//
//  LaunchAnnouncementSession.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 24/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Observation

@Observable
@MainActor
final class LaunchAnnouncementSession {
    static let shared = LaunchAnnouncementSession {
        ShortcutManager.shared.pendingAction != nil || URLSchemeManager.shared.pendingAction != nil
            || ShareManager.shared.hasPendingShare
    }

    enum Presentation {
        case undecided
        case banner
        case whatsNew
    }

    var presentation: Presentation = .undecided
    var hasExternalEntry = false
    var hasRequestedReview = false
    private let hasPendingEntry: () -> Bool

    var canPresentNews: Bool {
        presentation == .undecided && !hasExternalEntry && !hasPendingEntry() && !hasRequestedReview
    }

    init(hasPendingEntry: @escaping () -> Bool = { false }) {
        self.hasPendingEntry = hasPendingEntry
    }
}
