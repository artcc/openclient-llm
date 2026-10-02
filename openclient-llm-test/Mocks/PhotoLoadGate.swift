//
//  PhotoLoadGate.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 01/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class PhotoLoadGate {
    let started: XCTestExpectation
    private var continuation: CheckedContinuation<Data, Never>?
    private var isReleased = false

    init(started: XCTestExpectation) { self.started = started }

    func input(_ fileName: String) -> ChatViewModel.ImageInput {
        .init(fileName: fileName, loadData: { await self.load() })
    }

    func release() {
        isReleased = true
        let pending = continuation
        continuation = nil
        pending?.resume(returning: Data([1]))
    }

    private func load() async -> Data {
        guard !isReleased else { return Data([1]) }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
    }
}
