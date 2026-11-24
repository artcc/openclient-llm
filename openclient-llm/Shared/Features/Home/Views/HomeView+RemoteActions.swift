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

    func dismissNews(_ news: RemoteWhatsNew, performAction: Bool) {
        guard visibleNews?.id == news.id else { return }
        remoteWhatsNew = nil
        guard performAction, let action = news.action else { return }
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
