//
//  RemoteConfig.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 09/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

nonisolated struct RemoteConfig: Codable, Equatable, Sendable {
    struct MaintenanceMode: Codable, Equatable, Sendable {
        let enabled: Bool
    }

    struct AppUpdate: Codable, Equatable, Sendable {
        let ios: PlatformUpdate
        let macos: PlatformUpdate
    }

    struct PlatformUpdate: Codable, Equatable, Sendable {
        let enabled: Bool
        let forceUpdate: Bool
        let latestVersion: String
        let updateURL: URL
    }

    struct Banner: Codable, Equatable, Sendable {
        let active: Bool
        let dismissBannerKey: String
        let platforms: [Platform]
        let items: [String: Item]
    }

    struct SettingsSection: Codable, Equatable, Sendable {
        let tipOption: Bool
        let showIconPacks: [String]?
    }

    struct Item: Codable, Equatable, Sendable {
        let title: String
        let subtitle: String
        let cta: String
        let action: Action
        let url: String
        let emoji: String
    }

    enum Platform: String, Codable, Equatable, Sendable {
        case ios
        case macos
    }

    enum Action: String, Codable, Equatable, Sendable {
        case close
        case openURL = "open_url"
        case feedback
        case tip
        case writeReview = "write_review"
    }

    let schemaVersion: Int
    let maintenanceMode: MaintenanceMode
    let appUpdate: AppUpdate
    let banner: Banner
    let settingsSection: SettingsSection?
    private(set) var whatsNew: WhatsNew?

    var isTipJarEnabled: Bool {
        settingsSection?.tipOption ?? true
    }

    var showIconPacks: [String]? {
        settingsSection?.showIconPacks
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case maintenanceMode = "maintenance_mode"
        case appUpdate = "app_update"
        case banner
        case settingsSection = "settings_section"
        case whatsNew = "whats_new"
    }
}

extension RemoteConfig {
    static func languageCandidates(for identifier: String) -> [String] {
        let region = identifier.prefix { $0 != "@" }.replacingOccurrences(of: "_", with: "-")
        return [region, String(region.prefix { $0 != "-" }), "en"]
    }

    static func isValidWebURL(_ url: URL?) -> Bool {
        guard let url, let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return false }
        return true
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        maintenanceMode = try container.decode(MaintenanceMode.self, forKey: .maintenanceMode)
        appUpdate = try container.decode(AppUpdate.self, forKey: .appUpdate)
        banner = try container.decode(Banner.self, forKey: .banner)
        settingsSection = try container.decodeIfPresent(SettingsSection.self, forKey: .settingsSection)
        // Optional release notes must never suppress maintenance or forced-update instructions.
        whatsNew = try? container.decode(WhatsNew.self, forKey: .whatsNew)
    }
}

// MARK: - Coding Keys

private extension RemoteConfig.PlatformUpdate {
    enum CodingKeys: String, CodingKey {
        case enabled
        case forceUpdate = "force_update"
        case latestVersion = "latest_version"
        case updateURL = "update_url"
    }
}

private extension RemoteConfig.Banner {
    enum CodingKeys: String, CodingKey {
        case active
        case dismissBannerKey = "dismiss_banner_key"
        case platforms
        case items
    }
}

private extension RemoteConfig.SettingsSection {
    enum CodingKeys: String, CodingKey {
        case tipOption = "tip_option"
        case showIconPacks = "show_icon_packs"
    }
}
