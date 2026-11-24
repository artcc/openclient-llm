//
//  HomeView+RemoteActions.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 24/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

extension HomeView {
    struct AnnouncementWebPage: Identifiable {
        let title: String
        let url: URL

        var id: URL { url }
    }

    func handleRemoteBannerAction() {
        guard let item = remoteBanner?.item else { return }
        onRemoteBannerDismiss()
        performRemoteAction(item.action, title: item.title, url: URL(string: item.url))
    }

    func handleExternalEntry() {
        pendingNewsAction = nil
        onExternalEntry()
    }

    func performPendingNewsAction() {
        guard let news = pendingNewsAction else { return }
        pendingNewsAction = nil
        guard !hasPendingExternalEntry, !LaunchAnnouncementSession.shared.hasExternalEntry,
              let action = news.action else { return }
        performRemoteAction(action, title: news.item.title, url: news.url)
    }

    private func performRemoteAction(_ action: RemoteConfig.Action, title: String, url: URL?) {
        switch action {
        case .close:
            break
        case .openURL:
            guard let url, RemoteConfig.isValidWebURL(url) else { return }
            announcementWebPage = AnnouncementWebPage(title: title, url: url)
        case .feedback:
            routeToSettings(.feedback)
        case .tip:
            routeToSettings(.tipJar)
        case .writeReview:
            if let url = Constants.URLs.writeReview { openURL(url) }
        }
    }
}
