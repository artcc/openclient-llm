//
//  EditImageToolTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 01/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class EditImageToolTests: XCTestCase {
    private let generation = MockGenerateImageUseCase()
    private let conversationId = UUID()
    private let image = ChatMessage.Attachment(
        type: .image, fileName: "original.png", mimeType: "image/png", fileRelativePath: "",
        transientData: Data([1, 2, 3])
    )
    private let output = GeneratedImage(data: Data([4, 5, 6]), mimeType: "image/png", revisedPrompt: nil)

    func test_execute_selectedHistoricalImage_forwardsOnlyItsBytesAndReturnsTypedResult() async throws {
        // Given
        generation.result = .success(output)
        let other = ChatMessage.Attachment(
            type: .image, fileName: "other.png", mimeType: "image/png", fileRelativePath: "", transientData: Data([9])
        )
        let executor = makeExecutor()
        let sut = makeTool(executor, attachments: [image, other])

        // When
        let result = try await sut.execute(arguments: arguments(image.id))

        // Then
        XCTAssertEqual(generation.attachments, [[image]])
        XCTAssertEqual(generation.prompts, ["Change the background"])
        XCTAssertEqual(result.images, [output])
        XCTAssertFalse(result.text.contains(image.id.uuidString))
        XCTAssertFalse(result.text.contains(output.data.base64EncodedString()))
        XCTAssertFalse(executor.isAvailableForAdvertisement)
        XCTAssertFalse(sut.isAvailableForAdvertisement)
    }

    func test_execute_invalidReferencesAndArguments_doNotConsumeAttempt() async throws {
        // Given
        generation.result = .success(output)
        let executor = makeExecutor()
        let sut = makeTool(executor)
        let invalid = [
            "{}", arguments(UUID()),
            #"{"prompt":"Change","attachment_id":"https://example.com/image.png"}"#,
            "{\"prompt\":\"Change\",\"attachment_id\":\"\(image.id)\",\"attachments\":[]}",
            "{\"prompt\":\" \",\"attachment_id\":\"\(image.id)\"}",
            String(repeating: " ", count: 65_537)
        ]

        // When / Then
        for input in invalid {
            do {
                _ = try await sut.execute(arguments: input)
                XCTFail("Expected invalid input to be rejected")
            } catch {
                XCTAssertTrue(executor.isAvailableForAdvertisement)
            }
        }
        XCTAssertEqual(generation.executeCallCount, 0)
        _ = try await sut.execute(arguments: arguments(image.id))
        XCTAssertEqual(generation.executeCallCount, 1)
    }

    func test_execute_duplicateOrForeignAttachment_rejectsBeforeRequest() async throws {
        // Given
        let foreign = ChatMessage.Attachment(
            id: image.id, type: .image, fileName: "image.png", mimeType: "image/png",
            fileRelativePath: "Attachments/\(UUID())/\(image.id).png"
        )

        // When / Then
        for attachments in [[image, image], [foreign]] {
            let sut = makeTool(makeExecutor(), attachments: attachments)
            do {
                _ = try await sut.execute(arguments: arguments(image.id))
                XCTFail("Expected ambiguous or foreign image to be rejected")
            } catch {
                XCTAssertEqual(error as? EditImageTool.ExecutionError, .unknownImage)
            }
        }
        XCTAssertEqual(generation.executeCallCount, 0)
    }

    func test_execute_generationAndEditing_shareOneAttemptInEitherOrder() async throws {
        // Given
        generation.result = .success(output)
        for editFirst in [true, false] {
            let executor = makeExecutor()
            let sut = makeTool(executor)

            // When
            if editFirst {
                _ = try await sut.execute(arguments: arguments(image.id))
            } else {
                _ = try await executor.execute(arguments: #"{"prompt":"New image"}"#)
            }

            // Then
            do {
                if editFirst {
                    _ = try await executor.execute(arguments: #"{"prompt":"New image"}"#)
                } else {
                    _ = try await sut.execute(arguments: arguments(image.id))
                }
                XCTFail("Expected shared turn limit")
            } catch {
                XCTAssertEqual(error as? GenerateImageTool.ExecutionError, .turnLimitReached)
            }
        }
        XCTAssertEqual(generation.executeCallCount, 2)
    }

    func test_execute_failedEdit_blocksGenerationFallback() async throws {
        // Given
        generation.result = .failure(APIError.rateLimited)
        let executor = makeExecutor()
        let sut = makeTool(executor)

        // When
        do {
            _ = try await sut.execute(arguments: arguments(image.id))
            XCTFail("Expected edit failure")
        } catch {
            XCTAssertEqual(error as? GenerateImageTool.ExecutionError, .requestFailed)
        }

        // Then
        do {
            _ = try await executor.execute(arguments: #"{"prompt":"Try generating instead"}"#)
            XCTFail("Expected consumed attempt")
        } catch {
            XCTAssertEqual(error as? GenerateImageTool.ExecutionError, .turnLimitReached)
        }
        XCTAssertEqual(generation.executeCallCount, 1)
    }

    func test_execute_revokedWhileReserving_doesNotStartRequest() async throws {
        // Given
        let availability = Availability()
        let executor = GenerateImageTool(
            modelId: "editor", generateImageUseCase: generation,
            onAttempt: { _ in availability.isAvailable = false }
        )
        let sut = EditImageTool(
            attachments: [image], conversationId: conversationId, executor: executor,
            isAvailable: { availability.isAvailable }
        )

        // When / Then
        do {
            _ = try await sut.execute(arguments: arguments(image.id))
            XCTFail("Expected revoked edit to be rejected")
        } catch {
            XCTAssertEqual(error as? GenerateImageTool.ExecutionError, .unavailable)
        }
        XCTAssertEqual(generation.executeCallCount, 0)
    }

    func test_execute_dedicatedTransport_uploadsSelectedImageToEditsOnly() async throws {
        // Given
        let api = MockAPIClient()
        api.multipartResult = ImageGenerationResponse(data: [
            .init(url: nil, b64Json: output.data.base64EncodedString(), revisedPrompt: nil)
        ])
        let useCase = GenerateImageUseCase(
            repository: ImageGenerationRepository(apiClient: api),
            attachmentRepository: MockAttachmentRepository(),
            prepareImageAttachmentUseCase: MockPrepareImageAttachmentUseCase()
        )
        let executor = GenerateImageTool(modelId: "editor", generateImageUseCase: useCase)

        // When
        _ = try await makeTool(executor).execute(arguments: arguments(image.id))

        // Then
        XCTAssertEqual(api.lastMultipartEndpoint, "images/edits")
        XCTAssertEqual(api.lastMultipartFiles?.map(\.data), [image.transientData].compactMap { $0 })
        XCTAssertEqual(api.lastMultipartFields?["prompt"], "Change the background")
        XCTAssertNil(api.lastRequestEndpoint)
    }

    func test_execute_unavailableAfterPreparation_doesNotUploadImage() async throws {
        // Given
        let api = MockAPIClient()
        let useCase = GenerateImageUseCase(
            repository: ImageGenerationRepository(apiClient: api),
            attachmentRepository: MockAttachmentRepository(),
            prepareImageAttachmentUseCase: MockPrepareImageAttachmentUseCase(),
            isRequestAvailable: { _ in false }
        )
        let executor = GenerateImageTool(modelId: "editor", generateImageUseCase: useCase)

        // When / Then
        do {
            _ = try await makeTool(executor).execute(arguments: arguments(image.id))
            XCTFail("Expected cancellation before upload")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertNil(api.lastMultipartEndpoint)
        XCTAssertNil(api.lastRequestEndpoint)
    }

    private func makeExecutor() -> GenerateImageTool {
        GenerateImageTool(modelId: "editor", generateImageUseCase: generation)
    }

    private func makeTool(
        _ executor: GenerateImageTool,
        attachments: [ChatMessage.Attachment]? = nil
    ) -> EditImageTool {
        EditImageTool(
            attachments: attachments ?? [image], conversationId: conversationId,
            executor: executor, isAvailable: { true }
        )
    }

    private func arguments(_ id: UUID) -> String {
        "{\"prompt\":\"Change the background\",\"attachment_id\":\"\(id.uuidString)\"}"
    }

    private final class Availability {
        var isAvailable = true
    }
}
