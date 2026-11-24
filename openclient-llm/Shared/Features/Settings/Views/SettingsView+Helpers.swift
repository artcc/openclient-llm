//
//  SettingsView+Helpers.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 08/04/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI
#if os(iOS)
import SwiftUI
#endif

// MARK: - Helpers

extension SettingsView {
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    func requestAppReview() {
        guard let url = Constants.URLs.writeReview else { return }
#if os(iOS)
        UIApplication.shared.open(url)
#else
        NSWorkspace.shared.open(url)
#endif
    }
}
