//
//  RemoteWhatsNewTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 24/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class RemoteWhatsNewTests: XCTestCase {
    func test_resolvedWhatsNew_localizedItems_prefersRegionThenLanguageThenEnglish() throws {
        let config = try decodeConfig(whatsNew: newsBlock())

        for (locale, expected) in [("es_MX", "México"), ("es-ES", "Español"), ("fr-CA", "English")] {
            let news = try XCTUnwrap(config.resolvedWhatsNew(
                installedVersion: "2.0", platform: .ios, localeIdentifier: locale
            ))
            XCTAssertEqual(news.item.title, expected, locale)
            XCTAssertEqual(news.item.highlights.map(\.body), ["\(expected) detail"], locale)
        }
    }

    func test_resolvedWhatsNew_installedVersionOrPlatformNotTargeted_returnsNil() throws {
        let config = try decodeConfig(whatsNew: newsBlock())

        let otherVersions: [String?] = [nil, "1.9", "2.0.1", "2.0.0"]
        for version in otherVersions {
            XCTAssertNil(config.resolvedWhatsNew(installedVersion: version, platform: .ios, localeIdentifier: "en"))
        }
        XCTAssertNil(config.resolvedWhatsNew(installedVersion: "2.0", platform: .macos, localeIdentifier: "en"))
    }

    func test_resolvedWhatsNew_corruptRegionalItem_fallsBackToValidLanguage() throws {
        let config = try decodeConfig(whatsNew: newsBlock(regionalItem: #"{"title":42}"#))

        let news = config.resolvedWhatsNew(installedVersion: "2.0", platform: .ios, localeIdentifier: "es-MX")

        XCTAssertEqual(news?.item.title, "Español")
    }

    func test_resolvedWhatsNew_writeReviewAction_exposesLocalizedCTAWithoutURL() throws {
        let config = try decodeConfig(whatsNew: newsBlock(action: "write_review"))

        let news = try XCTUnwrap(config.resolvedWhatsNew(
            installedVersion: "2.0", platform: .ios, localeIdentifier: "es"
        ))

        XCTAssertEqual(news.action, .writeReview)
        XCTAssertEqual(news.actionTitle, "Español CTA")
        XCTAssertNil(news.url)
    }

    func test_resolvedWhatsNew_unknownAction_keepsHighlightsWithoutCTA() throws {
        let config = try decodeConfig(whatsNew: newsBlock(action: "future_action"))

        let news = try XCTUnwrap(config.resolvedWhatsNew(
            installedVersion: "2.0", platform: .ios, localeIdentifier: "en"
        ))

        XCTAssertEqual(news.item.highlights.map(\.title), ["English highlight"])
        XCTAssertNil(news.action)
        XCTAssertNil(news.actionTitle)
    }

    func test_decode_malformedWhatsNew_preservesMaintenanceAndForcedUpdate() throws {
        let config = try decodeConfig(whatsNew: #"{"active":true,"items":[]}"#)

        XCTAssertNil(config.whatsNew)
        XCTAssertTrue(config.maintenanceMode.enabled)
        XCTAssertTrue(config.appUpdate.ios.forceUpdate)
        XCTAssertEqual(config.appUpdate.ios.latestVersion, "3.0")
    }

    func test_resolvedWhatsNew_openURL_exposesCTAOnlyForValidWebURL() throws {
        let validURL = "https://example.org/releases"
        for url in [validURL, "release/2", "file:///release", "https://user@example.org/release"] {
            let config = try decodeConfig(whatsNew: newsBlock(action: "open_url", url: url))
            let news = try XCTUnwrap(config.resolvedWhatsNew(
                installedVersion: "2.0", platform: .ios, localeIdentifier: "en"
            ))

            XCTAssertEqual(news.action, url == validURL ? .openURL : nil, url)
            XCTAssertEqual(news.actionTitle, url == validURL ? "English CTA" : nil, url)
            XCTAssertEqual(news.url?.absoluteString, url == validURL ? url : nil, url)
        }
    }

    func test_resolvedWhatsNew_closeAction_keepsNewsWithoutContextualCTA() throws {
        let config = try decodeConfig(whatsNew: newsBlock(action: "close"))

        let news = try XCTUnwrap(config.resolvedWhatsNew(
            installedVersion: "2.0", platform: .ios, localeIdentifier: "en"
        ))

        XCTAssertNil(news.action)
        XCTAssertNil(news.actionTitle)
    }

    func test_resolvedWhatsNew_inactiveCampaign_returnsNilForTargetedRelease() throws {
        let config = try decodeConfig(whatsNew: newsBlock(active: false))

        XCTAssertEqual(config.whatsNew?.active, false)
        XCTAssertNil(config.resolvedWhatsNew(installedVersion: "2.0", platform: .ios, localeIdentifier: "en"))
    }
}

private extension RemoteWhatsNewTests {
    func newsBlock(
        action: String = "write_review", regionalItem: String? = nil, url: String? = nil, active: Bool = true
    ) -> String {
        func item(_ title: String) -> String {
            """
            {"title":"\(title)", "action_title":"\(title) CTA", "highlights":[
              {"symbol":"star", "title":"\(title) highlight", "body":"\(title) detail"}
            ]}
            """
        }
        let urlField = url.map { "\"url\": \"\($0)\"," } ?? ""
        return """
        {
          "active": \(active), "id": "release-2", "version": "2.0", "platforms": ["ios"], "action": "\(action)",
          \(urlField)
          "items": {"es-MX": \(regionalItem ?? item("México")), "es": \(item("Español")), "en": \(item("English"))}
        }
        """
    }

    func decodeConfig(whatsNew: String) throws -> RemoteConfig {
        let update = #"{"enabled":true,"force_update":true,"latest_version":"3.0","update_url":"https://example.com"}"#
        let json = """
        {
          "schema_version": 1,
          "maintenance_mode": {"enabled":true},
          "app_update": {"ios":\(update),"macos":\(update)},
          "banner": {"active":false,"dismiss_banner_key":"banner","platforms":[],"items":{}},
          "whats_new": \(whatsNew)
        }
        """
        return try JSONDecoder().decode(RemoteConfig.self, from: Data(json.utf8))
    }
}
