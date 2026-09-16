//
//  CloudContainerProvider.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 10/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

nonisolated protocol CloudContainerProviding: Sendable {
    func isAvailable() -> Bool
    func isMetadataReady(for session: CloudSyncSession) -> Bool
    func containerURL() -> URL?
    func identityData() -> Data?
    func currentSession() -> CloudSyncSession?
}

nonisolated extension CloudContainerProviding {
    func currentSession() -> CloudSyncSession? {
        guard isAvailable(),
              let firstIdentity = identityData(),
              let containerURL = containerURL()?.standardizedFileURL,
              let secondIdentity = identityData(),
              firstIdentity == secondIdentity else {
            return nil
        }
        return CloudSyncSession(containerURL: containerURL, identity: firstIdentity)
    }
}

// Safety: FileManager is thread-safe per Apple documentation. All stored properties are immutable (`let`).
nonisolated struct UbiquityCloudContainerProvider: CloudContainerProviding, @unchecked Sendable {
    private let fileManager: FileManager
    private let metadataReadiness: CloudMetadataReadiness

    init(
        fileManager: FileManager,
        metadataReadiness: CloudMetadataReadiness = .shared
    ) {
        self.fileManager = fileManager
        self.metadataReadiness = metadataReadiness
    }

    func isAvailable() -> Bool {
        fileManager.ubiquityIdentityToken != nil && containerURL() != nil
    }

    func isMetadataReady(for session: CloudSyncSession) -> Bool {
        metadataReadiness.isReady(for: session)
    }

    func containerURL() -> URL? {
        fileManager.url(forUbiquityContainerIdentifier: nil)
    }

    func identityData() -> Data? {
        guard let token = fileManager.ubiquityIdentityToken else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false)
    }

    func currentSession() -> CloudSyncSession? {
        guard let firstIdentity = identityData(),
              let containerURL = containerURL()?.standardizedFileURL,
              let secondIdentity = identityData(),
              firstIdentity == secondIdentity else {
            return nil
        }
        return CloudSyncSession(containerURL: containerURL, identity: firstIdentity)
    }
}

nonisolated struct FixedCloudContainerProvider: CloudContainerProviding {
    private let url: URL?
    private let available: Bool
    private let metadataReady: Bool
    private let identity: Data

    init(
        url: URL?,
        available: Bool = true,
        metadataReady: Bool = true,
        identity: Data = Data("fixed-cloud-container".utf8)
    ) {
        self.url = url
        self.available = available
        self.metadataReady = metadataReady
        self.identity = identity
    }

    func isAvailable() -> Bool {
        available && url != nil
    }

    func isMetadataReady(for session: CloudSyncSession) -> Bool {
        metadataReady
    }

    func containerURL() -> URL? {
        url
    }

    func identityData() -> Data? {
        available ? identity : nil
    }

    func currentSession() -> CloudSyncSession? {
        guard available, let url else { return nil }
        return CloudSyncSession(containerURL: url.standardizedFileURL, identity: identity)
    }
}
