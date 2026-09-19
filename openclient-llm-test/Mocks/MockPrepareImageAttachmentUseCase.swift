//
//  MockPrepareImageAttachmentUseCase.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 09/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation
@testable import openclient_llm

// Safety: Tests configure `result` before each awaited execution and never mutate it while `execute` is running.
nonisolated final class MockPrepareImageAttachmentUseCase: PrepareImageAttachmentUseCaseProtocol, @unchecked Sendable {
    // MARK: - Properties

    var result: Result<PreparedImageAttachment, Error>?

    // MARK: - Execute

    @concurrent
    func execute(data: Data, fileName: String) async throws -> PreparedImageAttachment {
        if let result {
            return try result.get()
        }
        return PreparedImageAttachment(data: data, fileName: fileName, mimeType: "image/jpeg")
    }
}
