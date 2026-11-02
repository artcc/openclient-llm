//
//  ServerRequestRedirectDelegate.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 02/11/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

nonisolated final class ServerRequestRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = ServerRequestRedirectDelegate()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        // Custom headers may contain credentials; do not forward the request to another origin.
        completionHandler(Self.hasSameOrigin(task.originalRequest?.url, request.url) ? request : nil)
    }

    static func hasSameOrigin(_ source: URL?, _ destination: URL?) -> Bool {
        guard let source, let destination,
              let scheme = source.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = source.host?.lowercased() else { return false }
        let defaultPort = scheme == "https" ? 443 : 80
        return scheme == destination.scheme?.lowercased()
            && host == destination.host?.lowercased()
            && (source.port ?? defaultPort) == (destination.port ?? defaultPort)
    }
}
