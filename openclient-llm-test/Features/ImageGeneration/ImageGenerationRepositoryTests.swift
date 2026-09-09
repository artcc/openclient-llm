//
//  ImageGenerationRepositoryTests.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 09/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class ImageGenerationRepositoryTests: XCTestCase {
    func test_generateImage_withBase64Response_returnsDecodedImage() async throws {
        // Given
        let imageData = Data([1, 2, 3])
        let apiClient = MockAPIClient()
        apiClient.requestResult = ImageGenerationResponse(data: [
            .init(url: nil, b64Json: imageData.base64EncodedString(), revisedPrompt: "A lunar cat")
        ])
        let sut = ImageGenerationRepository(apiClient: apiClient)

        // When
        let result = try await sut.generateImage(prompt: "A cat", model: "gpt-image-2", images: [])

        // Then
        XCTAssertEqual(result.data, imageData)
        XCTAssertEqual(result.mimeType, "image/png")
        XCTAssertEqual(result.revisedPrompt, "A lunar cat")
        XCTAssertEqual(apiClient.lastRequestEndpoint, "images/generations")
        XCTAssertEqual(apiClient.lastRequestTimeoutInterval, 600)
        XCTAssertNil(apiClient.lastMultipartEndpoint)
    }

    func test_generateImage_multipleImages_sendsOrderedMultipartFilesAndFields() async throws {
        // Given
        let images = [
            PreparedImageAttachment(data: Data([1, 2]), fileName: "image-1.png", mimeType: "image/png"),
            PreparedImageAttachment(data: Data([3, 4, 5]), fileName: "image-2.jpg", mimeType: "image/jpeg")
        ]
        let imageData = Data([6, 7, 8])
        let apiClient = MockAPIClient()
        apiClient.multipartResult = ImageGenerationResponse(data: [
            .init(
                url: "https://example.com/unused.png",
                b64Json: imageData.base64EncodedString(),
                revisedPrompt: "Two cats on the moon"
            )
        ])
        apiClient.downloadError = APIError.serverUnreachable
        let sut = ImageGenerationRepository(apiClient: apiClient)

        // When
        let result = try await sut.generateImage(prompt: "Combine these cats", model: "gpt-image-2", images: images)

        // Then
        XCTAssertEqual(apiClient.lastMultipartEndpoint, "images/edits")
        XCTAssertEqual(apiClient.lastMultipartTimeoutInterval, 600)
        XCTAssertEqual(apiClient.lastMultipartFields, [
            "model": "gpt-image-2",
            "prompt": "Combine these cats",
            "n": "1"
        ])
        XCTAssertNil(apiClient.lastMultipartFields?["response_format"])
        XCTAssertNil(apiClient.lastMultipartFields?["size"])
        let files = try XCTUnwrap(apiClient.lastMultipartFiles)
        XCTAssertEqual(files.map(\.field), ["image", "image"])
        XCTAssertEqual(files.map(\.data), images.map(\.data))
        XCTAssertEqual(files.map(\.fileName), ["image-1.png", "image-2.jpg"])
        XCTAssertEqual(files.map(\.mimeType), ["image/png", "image/jpeg"])
        XCTAssertNil(apiClient.lastRequestEndpoint)
        XCTAssertEqual(result.data, imageData)
        XCTAssertEqual(result.mimeType, "image/png")
        XCTAssertEqual(result.revisedPrompt, "Two cats on the moon")
    }

    func test_generateImage_urlResponse_downloadsImageForBothEndpoints() async throws {
        for images in [[], [preparedImage]] {
            // Given
            let response = ImageGenerationResponse(data: [
                .init(url: "https://example.com/generated.webp", b64Json: nil, revisedPrompt: "A blue cat")
            ])
            let apiClient = MockAPIClient()
            apiClient.requestResult = response
            apiClient.multipartResult = response
            apiClient.downloadResult = (Data([9, 8, 7]), "image/webp")
            let sut = ImageGenerationRepository(apiClient: apiClient)

            // When
            let result = try await sut.generateImage(prompt: "A cat", model: "gpt-image-2", images: images)

            // Then
            XCTAssertEqual(result.data, Data([9, 8, 7]))
            XCTAssertEqual(result.mimeType, "image/webp")
            XCTAssertEqual(result.revisedPrompt, "A blue cat")
            XCTAssertEqual(apiClient.lastRequestEndpoint, images.isEmpty ? "images/generations" : nil)
            XCTAssertEqual(apiClient.lastMultipartEndpoint, images.isEmpty ? nil : "images/edits")
        }
    }

    func test_generateImage_editRequestError_propagatesWithoutGenerationFallback() async {
        // Given
        let apiClient = MockAPIClient()
        apiClient.multipartError = APIError.httpError(statusCode: 400)
        let sut = ImageGenerationRepository(apiClient: apiClient)

        // When
        do {
            _ = try await sut.generateImage(prompt: "Edit this cat", model: "gpt-image-2", images: [preparedImage])
            XCTFail("Expected the edit request to fail")
        } catch {
            // Then
            XCTAssertEqual(error as? APIError, .httpError(statusCode: 400))
        }
        XCTAssertEqual(apiClient.lastMultipartEndpoint, "images/edits")
        XCTAssertNil(apiClient.lastRequestEndpoint)
    }

    func test_generateImage_invalidEditResponse_throwsWithoutGenerationFallback() async {
        let responses = [
            ImageGenerationResponse(data: []),
            ImageGenerationResponse(data: [.init(url: nil, b64Json: nil, revisedPrompt: nil)]),
            ImageGenerationResponse(data: [.init(url: nil, b64Json: "not-base64!", revisedPrompt: nil)]),
            ImageGenerationResponse(data: [.init(url: nil, b64Json: "", revisedPrompt: nil)])
        ]
        for response in responses {
            // Given
            let apiClient = MockAPIClient()
            apiClient.multipartResult = response
            let sut = ImageGenerationRepository(apiClient: apiClient)

            // When
            do {
                _ = try await sut.generateImage(prompt: "Edit this cat", model: "gpt-image-2", images: [preparedImage])
                XCTFail("Expected invalid response to be rejected")
            } catch {
                // Then
                XCTAssertEqual(error as? APIError, .invalidResponse)
            }
            XCTAssertEqual(apiClient.lastMultipartEndpoint, "images/edits")
            XCTAssertNil(apiClient.lastRequestEndpoint)
        }
    }

    func test_generateImage_invalidDownloadedImage_throwsWithoutGenerationFallback() async {
        for download in [(Data(), "image/png"), (Data([1, 2]), "text/html")] {
            // Given
            let apiClient = MockAPIClient()
            apiClient.multipartResult = ImageGenerationResponse(data: [
                .init(url: "https://example.com/generated.png", b64Json: nil, revisedPrompt: nil)
            ])
            apiClient.downloadResult = download
            let sut = ImageGenerationRepository(apiClient: apiClient)

            // When
            do {
                _ = try await sut.generateImage(prompt: "Edit this cat", model: "gpt-image-2", images: [preparedImage])
                XCTFail("Expected invalid downloaded image to be rejected")
            } catch {
                // Then
                XCTAssertEqual(error as? APIError, .invalidResponse)
            }
            XCTAssertNil(apiClient.lastRequestEndpoint)
        }
    }

    func test_generateImage_downloadError_propagatesWithoutGenerationFallback() async {
        // Given
        let apiClient = MockAPIClient()
        apiClient.multipartResult = ImageGenerationResponse(data: [
            .init(url: "https://example.com/generated.png", b64Json: nil, revisedPrompt: nil)
        ])
        apiClient.downloadError = APIError.serverUnreachable
        let sut = ImageGenerationRepository(apiClient: apiClient)

        // When
        do {
            _ = try await sut.generateImage(prompt: "Edit this cat", model: "gpt-image-2", images: [preparedImage])
            XCTFail("Expected the download error to propagate")
        } catch {
            // Then
            XCTAssertEqual(error as? APIError, .serverUnreachable)
        }
        XCTAssertNil(apiClient.lastRequestEndpoint)
    }

    func test_generateImage_cancelledEditRequest_propagatesCancellationWithoutGenerationFallback() async {
        // Given
        let apiClient = MockAPIClient()
        apiClient.multipartError = CancellationError()
        let sut = ImageGenerationRepository(apiClient: apiClient)

        // When
        do {
            _ = try await sut.generateImage(prompt: "Edit this cat", model: "gpt-image-2", images: [preparedImage])
            XCTFail("Expected cancellation to propagate")
        } catch {
            // Then
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertNil(apiClient.lastRequestEndpoint)
    }

    func test_generateImage_resolutionInPrompt_preservesPromptWithoutSendingSize() async throws {
        let prompts = [
            "Generate this image at the maximum supported resolution",
            "Generate a landscape at 3840x2160"
        ]
        for prompt in prompts {
            for images in [[], [preparedImage]] {
                // Given
                let apiClient = MockAPIClient()
                let response = ImageGenerationResponse(data: [
                    .init(url: nil, b64Json: Data([1, 2, 3]).base64EncodedString(), revisedPrompt: nil)
                ])
                apiClient.requestResult = response
                apiClient.multipartResult = response
                let sut = ImageGenerationRepository(apiClient: apiClient)

                // When
                _ = try await sut.generateImage(prompt: prompt, model: "image-model", images: images)

                // Then
                if images.isEmpty {
                    let body = try XCTUnwrap(apiClient.lastRequestBody)
                    let json = try JSONEncoder().encode(body)
                    let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
                    XCTAssertEqual(fields["prompt"] as? String, prompt)
                    XCTAssertNil(fields["size"])
                } else {
                    XCTAssertEqual(apiClient.lastMultipartFields?["prompt"], prompt)
                    XCTAssertNil(apiClient.lastMultipartFields?["size"])
                }
            }
        }
    }

    // MARK: - Private

    private var preparedImage: PreparedImageAttachment {
        PreparedImageAttachment(data: Data([1, 2, 3]), fileName: "image-1.png", mimeType: "image/png")
    }
}
