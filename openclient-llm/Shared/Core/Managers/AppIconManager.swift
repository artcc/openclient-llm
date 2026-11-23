//
//  AppIconManager.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 26/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

#if os(iOS)
import UIKit
#else
import Foundation
#endif

@MainActor
protocol AppIconManagerProtocol {
    var supportsAlternateIcons: Bool { get }
    var selectedIcon: AppIcon { get }

    func setIcon(_ icon: AppIcon) async throws
}

@MainActor
struct AppIconManager: AppIconManagerProtocol {
#if os(iOS)
    private let application: UIApplication

    init(application: UIApplication = .shared) {
        self.application = application
    }
#else
    init() {}
#endif

    var supportsAlternateIcons: Bool {
#if os(iOS)
        application.supportsAlternateIcons
#else
        false
#endif
    }

    var selectedIcon: AppIcon {
#if os(iOS)
        AppIcon(alternateIconName: application.alternateIconName)
#else
            .defaultIcon
#endif
    }

    func setIcon(_ icon: AppIcon) async throws {
#if os(iOS)
        guard supportsAlternateIcons else {
            throw AppIconManagerError.alternateIconsUnavailable
        }
        guard selectedIcon != icon else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            application.setAlternateIconName(icon.alternateIconName) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
#else
        _ = icon
        throw AppIconManagerError.alternateIconsUnavailable
#endif
    }
}

private enum AppIconManagerError: Error {
    case alternateIconsUnavailable
}
