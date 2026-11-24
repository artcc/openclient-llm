//
//  Constants.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

enum Constants {
    // MARK: - App

    enum App {
        static let appStoreId = "id6761379499"
    }

    // MARK: - URLs

    enum URLs {
        private static let supportedLegalLanguages: Set<String> = [
            "de",
            "el",
            "en",
            "es",
            "fr",
            "ja",
            "it",
            "nl",
            "pt",
            "sv"
        ]

        private static var legalLanguageCode: String {
            let code = Locale.current.language.languageCode?.identifier ?? "en"
            return supportedLegalLanguages.contains(code) ? code : "en"
        }

        static var termsOfUse: URL? {
            URL(string: "https://www.arturocarreterocalvo.com/openclient-llm/legal/terms-app-\(legalLanguageCode)")
        }

        static var privacyPolicy: URL? {
            URL(string: "https://www.arturocarreterocalvo.com/openclient-llm/legal/privacy-app-\(legalLanguageCode)")
        }

        static let authorGitHub = URL(string: "https://github.com/ArtCC")
        static let writeReview = URL(
            string: "https://apps.apple.com/app/\(Constants.App.appStoreId)?action=write-review"
        )
        static let manageSubscriptions = URL(string: "https://apps.apple.com/account/subscriptions")
#if DEBUG
        static let remoteConfig = URL(string: "https://openclient-artcc05.web.app/config-dev.json")
#else
        static let remoteConfig = URL(string: "https://openclient-artcc05.web.app/config.json")
#endif
        static let serverUrl = "http://localhost:4000"
    }
}
