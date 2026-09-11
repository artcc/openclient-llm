//
//  ModelsRepositoryTests.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class ModelsRepositoryTests: XCTestCase {
    func test_fetchModelInfo_chatWithImageOutput_preservesModeAndCapabilities() async throws {
        // Given
        let response = try decodeModelInfo("""
        {
            "data": [{
                "model_name": "studio-assistant",
                "model_info": {
                    "mode": "chat",
                    "supports_vision": true,
                    "supports_function_calling": true,
                    "supports_parallel_function_calling": true,
                    "supports_response_schema": true,
                    "supports_web_search": true,
                    "supported_output_modalities": ["text", "image", "image"]
                }
            }]
        }
        """)
        let apiClient = MockAPIClient()
        apiClient.requestResult = response
        let sut = ModelsRepository(apiClient: apiClient)

        // When
        let models = try await sut.fetchModelInfo()

        // Then
        let model = try XCTUnwrap(models.first)
        XCTAssertEqual(apiClient.lastRequestEndpoint, "model/info")
        XCTAssertEqual(response.data.first?.modelInfo?.supportedOutputModalities, ["text", "image", "image"])
        XCTAssertEqual(model.mode, .chat)
        XCTAssertEqual(model.capabilities, [
            .vision, .functionCalling, .parallelFunctionCalling, .jsonSchema, .webSearch, .imageGeneration
        ])
        XCTAssertTrue(model.isVisionSpecialist)
        XCTAssertTrue(model.isImageGenerationSpecialist)
    }

    func test_fetchModelInfo_imageOutputWithoutVision_enablesOnlyGeneration() async throws {
        // Given
        let response = try decodeModelInfo("""
        {
            "data": [{
                "model_name": "studio-assistant",
                "model_info": {
                    "mode": "chat",
                    "supports_vision": false,
                    "supported_output_modalities": ["image"]
                }
            }]
        }
        """)
        let apiClient = MockAPIClient()
        apiClient.requestResult = response
        let sut = ModelsRepository(apiClient: apiClient)

        // When
        let models = try await sut.fetchModelInfo()

        // Then
        let model = try XCTUnwrap(models.first)
        XCTAssertEqual(model.mode, .chat)
        XCTAssertEqual(model.capabilities, [.imageGeneration])
        XCTAssertFalse(model.isVisionSpecialist)
        XCTAssertTrue(model.isImageGenerationSpecialist)
    }

    func test_fetchModelInfo_noImageOutput_doesNotInferGenerationFromVisionOrName() async throws {
        // Given
        for modalitiesField in [
            "",
            ", \"supported_output_modalities\": null",
            ", \"supported_output_modalities\": []",
            ", \"supported_output_modalities\": [\"text\", \"audio\"]"
        ] {
            let response = try decodeModelInfo("""
            {
                "data": [{
                    "model_name": "gemini-2.5-flash-image",
                    "model_info": {
                        "mode": "chat",
                        "supports_vision": true\(modalitiesField)
                    }
                }]
            }
            """)
            let apiClient = MockAPIClient()
            apiClient.requestResult = response
            let sut = ModelsRepository(apiClient: apiClient)

            // When
            let models = try await sut.fetchModelInfo()

            // Then
            let model = try XCTUnwrap(models.first)
            XCTAssertEqual(model.mode, .chat, modalitiesField)
            XCTAssertEqual(model.capabilities, [.vision], modalitiesField)
            XCTAssertTrue(model.isVisionSpecialist, modalitiesField)
            XCTAssertFalse(model.isImageGenerationSpecialist, modalitiesField)
        }
    }

    func test_fetchModelInfo_dedicatedImageMode_preservesGenerationWithoutDuplicates() async throws {
        // Given
        for modalitiesField in ["", ", \"supported_output_modalities\": [\"text\", \"image\", \"image\"]"] {
            let response = try decodeModelInfo("""
            {
                "data": [{
                    "model_name": "studio-generator",
                    "model_info": {
                        "mode": "image_generation"\(modalitiesField)
                    }
                }]
            }
            """)
            let apiClient = MockAPIClient()
            apiClient.requestResult = response
            let sut = ModelsRepository(apiClient: apiClient)

            // When
            let models = try await sut.fetchModelInfo()

            // Then
            let model = try XCTUnwrap(models.first)
            XCTAssertEqual(model.mode, .imageGeneration, modalitiesField)
            XCTAssertEqual(model.capabilities, [.imageGeneration], modalitiesField)
            XCTAssertTrue(model.isImageGenerationSpecialist, modalitiesField)
        }
    }

    func test_fetchModelInfo_missingModelInfo_preservesMinimalModelFallback() async throws {
        // Given
        let response = try decodeModelInfo("""
        {"data": [{"model_name": "gemini-2.5-flash-image"}]}
        """)
        let apiClient = MockAPIClient()
        apiClient.requestResult = response
        let sut = ModelsRepository(apiClient: apiClient)

        // When
        let models = try await sut.fetchModelInfo()

        // Then
        let model = try XCTUnwrap(models.first)
        XCTAssertEqual(model.mode, .chat)
        XCTAssertTrue(model.capabilities.isEmpty)
        XCTAssertFalse(model.isImageGenerationSpecialist)
    }

    // MARK: - Private

    private func decodeModelInfo(_ json: String) throws -> ModelInfoResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ModelInfoResponse.self, from: Data(json.utf8))
    }
}
