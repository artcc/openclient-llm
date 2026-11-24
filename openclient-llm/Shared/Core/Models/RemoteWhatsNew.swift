//
//  RemoteWhatsNew.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 24/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

nonisolated struct RemoteWhatsNew: Identifiable, Equatable, Sendable {
    nonisolated struct Highlight: Codable, Equatable, Sendable {
        let symbol: String
        let title: String
        let body: String

        fileprivate var isValid: Bool {
            [symbol, title, body].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }

    nonisolated struct Item: Codable, Equatable, Sendable {
        let title: String
        let highlights: [Highlight]
        let actionTitle: String?

        fileprivate var isValid: Bool {
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !highlights.isEmpty && highlights.allSatisfy(\.isValid)
        }
    }

    let id: String
    let version: String
    let item: Item
    let action: RemoteConfig.Action?
    let url: URL?

    var actionTitle: String? { action == nil ? nil : item.actionTitle }
}

extension RemoteWhatsNew.Item {
    private enum CodingKeys: String, CodingKey {
        case title, highlights
        case actionTitle = "action_title"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        highlights = try container.decode([RemoteWhatsNew.Highlight].self, forKey: .highlights)
        actionTitle = try? container.decode(String.self, forKey: .actionTitle)
    }
}

extension RemoteConfig {
    nonisolated struct WhatsNew: Codable, Equatable, Sendable {
        let active: Bool
        let id: String
        let version: String
        let platforms: [Platform]
        let items: [String: RemoteWhatsNew.Item]
        let action: Action?
        let url: URL?
    }

    /// Resolves release notes only for the specified installed release, preferring region, language, then English.
    func resolvedWhatsNew(installedVersion: String?, platform: Platform, localeIdentifier: String) -> RemoteWhatsNew? {
        guard let news = whatsNew, news.active, news.version == installedVersion, !news.version.isEmpty,
              !news.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              news.platforms.contains(platform),
              let item = news.localizedItem(for: localeIdentifier) else { return nil }

        let action = news.resolvedAction(for: item, isTipJarEnabled: isTipJarEnabled)
        return RemoteWhatsNew(
            id: news.id,
            version: news.version,
            item: item,
            action: action,
            url: action == .openURL ? news.url : nil
        )
    }
}

extension RemoteConfig.WhatsNew {
    private enum CodingKeys: String, CodingKey {
        case active, id, version, platforms, items, action, url
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        active = try container.decode(Bool.self, forKey: .active)
        id = try container.decode(String.self, forKey: .id)
        version = try container.decode(String.self, forKey: .version)
        platforms = try container.decode([RemoteConfig.Platform].self, forKey: .platforms)
        items = try container.decode([String: LocalizedEntry].self, forKey: .items).compactMapValues(\.item)
        action = try? container.decode(RemoteConfig.Action.self, forKey: .action)
        url = try? container.decode(URL.self, forKey: .url)
    }
}

private extension RemoteConfig.WhatsNew {
    nonisolated struct LocalizedEntry: Decodable {
        let item: RemoteWhatsNew.Item?

        init(from decoder: Decoder) throws {
            item = try? RemoteWhatsNew.Item(from: decoder)
        }
    }

    func resolvedAction(for item: RemoteWhatsNew.Item, isTipJarEnabled: Bool) -> RemoteConfig.Action? {
        guard let action, let title = item.actionTitle,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        switch action {
        case .close:
            return nil
        case .openURL:
            return RemoteConfig.isValidWebURL(url) ? action : nil
        case .tip:
            return isTipJarEnabled ? action : nil
        case .feedback, .writeReview:
            return action
        }
    }

    func localizedItem(for identifier: String) -> RemoteWhatsNew.Item? {
        for candidate in RemoteConfig.languageCandidates(for: identifier) {
            guard let item = items.first(where: { $0.key.caseInsensitiveCompare(candidate) == .orderedSame })?.value,
                  item.isValid else { continue }
            return item
        }
        return nil
    }
}
