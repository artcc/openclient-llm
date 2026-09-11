//
//  GenerateImageUseCaseTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 09/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import UIKit
import XCTest
@testable import openclient_llm

@MainActor
final class GenerateImageUseCaseTests: XCTestCase {
    // MARK: - Properties

    private let repository = MockImageGenerationRepository()
    private let attachmentRepository = MockAttachmentRepository()

    private var sut: GenerateImageUseCase {
        GenerateImageUseCase(
            repository: repository,
            attachmentRepository: attachmentRepository
        )
    }

    // MARK: - Tests

    func test_execute_transientAndPersistedImages_preparesBytesInOrderWithSafeFilenames() async throws {
        // Given
        let transientData = makePNG(color: .red)
        let persistedData = makePNG(color: .blue)
        let transient = makeAttachment(data: transientData, fileName: "../private\r\nphoto.jpg")
        let persisted = makeAttachment(fileName: "restored.jpeg")
        var loadedIds: [UUID] = []
        attachmentRepository.loadHandler = { attachment in
            loadedIds.append(attachment.id)
            return persistedData
        }
        let expected = GeneratedImage(data: Data([7, 8, 9]), mimeType: "image/webp", revisedPrompt: "Two cats")
        repository.result = .success(expected)

        // When
        let result = try await sut.execute(
            prompt: "Combine these cats",
            model: "gpt-image-2",
            attachments: [transient, persisted]
        )

        // Then
        XCTAssertEqual(loadedIds, [persisted.id])
        XCTAssertEqual(repository.generateImageCallCount, 1)
        XCTAssertEqual(repository.lastPrompt, "Combine these cats")
        XCTAssertEqual(repository.lastModel, "gpt-image-2")
        XCTAssertEqual(repository.lastImages, [
            PreparedImageAttachment(data: transientData, fileName: "image-1.png", mimeType: "image/png"),
            PreparedImageAttachment(data: persistedData, fileName: "image-2.png", mimeType: "image/png")
        ])
        XCTAssertEqual(result, expected)
    }

    func test_execute_noAttachments_forwardsPromptAndModelWithNoImages() async throws {
        // Given
        let expected = GeneratedImage(data: Data([1, 2]), mimeType: "image/png", revisedPrompt: nil)
        repository.result = .success(expected)
        attachmentRepository.loadHandler = { _ in
            XCTFail("No attachments should be loaded")
            return Data()
        }
        let preparation = MockPrepareImageAttachmentUseCase()
        preparation.result = .failure(APIError.invalidRequest("Unexpected preparation"))
        let sut = GenerateImageUseCase(
            repository: repository,
            attachmentRepository: attachmentRepository,
            prepareImageAttachmentUseCase: preparation
        )

        // When
        let result = try await sut.execute(prompt: " A cat\n", model: "gpt-image-2", attachments: [])

        // Then
        XCTAssertEqual(repository.generateImageCallCount, 1)
        XCTAssertEqual(repository.lastPrompt, " A cat\n")
        XCTAssertEqual(repository.lastModel, "gpt-image-2")
        XCTAssertEqual(repository.lastImages, [])
        XCTAssertEqual(result, expected)
    }

    func test_execute_emptyPrompt_rejectsBeforeLoadingOrGenerating() async {
        // Given
        attachmentRepository.loadHandler = { _ in
            XCTFail("An empty prompt must be rejected before loading attachments")
            return Data()
        }
        for prompt in ["", " \n\t"] {
            // When
            do {
                _ = try await sut.execute(prompt: prompt, model: "gpt-image-2", attachments: [makeAttachment()])
                XCTFail("Expected an empty prompt to be rejected")
            } catch {
                // Then
                guard case ImageGenerationInputError.promptRequired = error else {
                    XCTFail("Expected promptRequired, got \(error)")
                    return
                }
            }
        }
        XCTAssertEqual(repository.generateImageCallCount, 0)
    }

    func test_execute_pdfAmongImages_rejectsBeforeLoadingOrGenerating() async {
        // Given
        let pdf = ChatMessage.Attachment(
            type: .pdf,
            fileName: "document.pdf",
            mimeType: "application/pdf",
            fileRelativePath: "Attachments/document.pdf"
        )
        attachmentRepository.loadHandler = { _ in
            XCTFail("PDF validation must precede loading any attachment")
            return Data()
        }

        // When
        do {
            _ = try await sut.execute(prompt: "A cat", model: "gpt-image-2", attachments: [makeAttachment(), pdf])
            XCTFail("Expected PDF attachments to be rejected")
        } catch {
            // Then
            guard case ImageGenerationInputError.imagesOnly = error else {
                XCTFail("Expected imagesOnly, got \(error)")
                return
            }
        }
        XCTAssertEqual(repository.generateImageCallCount, 0)
    }

    func test_execute_missingPersistedImage_throwsUnreadableImageWithoutGenerating() async {
        // Given
        attachmentRepository.loadError = AttachmentRepositoryError.fileNotFound

        // When
        do {
            _ = try await sut.execute(prompt: "A cat", model: "gpt-image-2", attachments: [makeAttachment()])
            XCTFail("Expected a missing attachment to be rejected")
        } catch {
            // Then
            guard case ImageGenerationInputError.unreadableImage = error else {
                XCTFail("Expected unreadableImage, got \(error)")
                return
            }
        }
        XCTAssertEqual(repository.generateImageCallCount, 0)
    }

    func test_execute_invalidImageBytes_rejectsWithoutLoadingFallbackOrGenerating() async {
        // Given
        let persistedData = makePNG(color: .red)
        attachmentRepository.loadHandler = { _ in
            XCTFail("Invalid transient bytes must not fall back to persisted bytes")
            return persistedData
        }
        for data in [Data(), Data("not an image".utf8)] {
            // When
            do {
                _ = try await sut.execute(
                    prompt: "A cat",
                    model: "gpt-image-2",
                    attachments: [makeAttachment(data: data)]
                )
                XCTFail("Expected invalid image bytes to be rejected")
            } catch {
                // Then
                XCTAssertEqual(error.localizedDescription, String(localized: "The selected file is not a valid image."))
            }
        }
        XCTAssertEqual(repository.generateImageCallCount, 0)
    }

    func test_execute_cancelledTask_neverLoadsAttachmentsOrCallsRepository() async {
        // Given
        attachmentRepository.loadHandler = { _ in
            XCTFail("A cancelled task must not load attachments")
            return Data()
        }
        let sut = sut
        for attachments in [[], [makeAttachment()]] {
            // When
            let task = Task { @MainActor in
                withUnsafeCurrentTask { $0?.cancel() }
                return try await sut.execute(prompt: "A cat", model: "gpt-image-2", attachments: attachments)
            }
            do {
                _ = try await task.value
                XCTFail("Expected cancellation to propagate")
            } catch {
                // Then
                XCTAssertTrue(error is CancellationError)
            }
        }
        XCTAssertEqual(repository.generateImageCallCount, 0)
    }

    func test_execute_cancelledWhileLoadingImage_stopsBeforeCallingRepository() async {
        // Given
        let imageData = makePNG(color: .blue)
        var loadCount = 0
        attachmentRepository.loadHandler = { _ in
            loadCount += 1
            withUnsafeCurrentTask { $0?.cancel() }
            return imageData
        }
        let sut = sut
        let attachment = makeAttachment()

        // When
        let task = Task { @MainActor in
            try await sut.execute(prompt: "A cat", model: "gpt-image-2", attachments: [attachment])
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation before the repository request")
        } catch {
            // Then
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(loadCount, 1)
        XCTAssertEqual(repository.generateImageCallCount, 0)
    }

    func test_execute_preparationCancelled_propagatesCancellationWithoutGenerating() async {
        // Given
        let preparation = MockPrepareImageAttachmentUseCase()
        preparation.result = .failure(CancellationError())
        let sut = GenerateImageUseCase(
            repository: repository,
            attachmentRepository: attachmentRepository,
            prepareImageAttachmentUseCase: preparation
        )

        // When
        do {
            _ = try await sut.execute(
                prompt: "A cat",
                model: "gpt-image-2",
                attachments: [makeAttachment(data: makePNG(color: .red))]
            )
            XCTFail("Expected preparation cancellation to propagate")
        } catch {
            // Then
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(repository.generateImageCallCount, 0)
    }

    func test_execute_gifAttachment_convertsBeforeSendingToImageRepository() async throws {
        // Given
        let data = try XCTUnwrap(Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"))
        repository.result = .success(GeneratedImage(data: Data([1]), mimeType: "image/png", revisedPrompt: nil))

        // When
        _ = try await sut.execute(
            prompt: "Edit this image", model: "image-model", attachments: [makeAttachment(data: data)]
        )

        // Then
        let image = try XCTUnwrap(repository.lastImages?.first)
        XCTAssertEqual(image.mimeType, "image/jpeg")
        XCTAssertEqual(image.fileName, "image-1.jpg")
        XCTAssertEqual(Array(image.data.prefix(2)), [0xFF, 0xD8])
    }

    func test_execute_repositoryError_propagatesError() async {
        // Given
        repository.result = .failure(APIError.rateLimited)

        // When
        do {
            _ = try await sut.execute(prompt: "A cat", model: "gpt-image-2", attachments: [])
            XCTFail("Expected the repository error to propagate")
        } catch {
            // Then
            XCTAssertEqual(error as? APIError, .rateLimited)
        }
        XCTAssertEqual(repository.generateImageCallCount, 1)
    }

    // MARK: - Private

    private func makeAttachment(data: Data? = nil, fileName: String = "photo.jpg") -> ChatMessage.Attachment {
        ChatMessage.Attachment(
            type: .image,
            fileName: fileName,
            mimeType: "image/jpeg",
            fileRelativePath: "Attachments/test/photo.jpg",
            transientData: data
        )
    }

    private func makePNG(color: UIColor) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2), format: format).pngData { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }
}
