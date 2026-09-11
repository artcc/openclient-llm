//
//  ChatViewModelImageToolsTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import XCTest
@testable import openclient_llm

@MainActor
final class ChatViewModelImageToolsTests: XCTestCase {
    // MARK: - Properties

    let settings = MockSettingsManager()
    let agent = MockAgentStreamUseCase()
    let stream = MockStreamMessageUseCase()
    let nativeGeneration = MockGenerateImageUseCase()
    let specialistGeneration = MockGenerateImageUseCase()
    let apiClient = MockAPIClient()
    let attachments = MockAttachmentRepository()
    let preparation = MockPrepareImageAttachmentUseCase()
    let save = MockSaveConversationUseCase()
    let preferences = MockGetChatPreferencesUseCase()
    let saveSelectedModel = MockSaveSelectedModelUseCase()
    let background = MockStreamingBackgroundUseCase()
    let principal = LLMModel(id: "principal", capabilities: [.functionCalling])
    let vision = LLMModel(id: "vision-specialist", capabilities: [.vision])
    let generator = LLMModel(id: "image-specialist", mode: .imageGeneration)
    let generatedImage = GeneratedImage(data: Data([4, 5, 6]), mimeType: "image/webp", revisedPrompt: nil)
    private var viewModels: [ChatViewModel] = []

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()
        settings.selectedModelId = principal.id
        settings.selectedVisionModelId = vision.id
        settings.selectedImageGenerationModelId = generator.id
        preferences.selectedModelId = principal.id
        agent.events = [.token("Response"), .completed]
        stream.chunks = [.token("Response")]
        specialistGeneration.result = .success(generatedImage)
        nativeGeneration.result = .success(generatedImage)
        apiClient.requestResult = try MockChatRepository().agentCompletionResult.get()
    }

    override func tearDown() async throws {
        for viewModel in viewModels {
            viewModel.errorDismissTask?.cancel()
            viewModel.mcpSettingsObservationTask?.cancel()
            viewModel.mcpDiscoveryTask?.cancel()
            viewModel.streamTask?.cancel()
            await viewModel.streamTask?.value
            _ = await viewModel.persistenceTask?.value
        }
        viewModels = []
        try await super.tearDown()
    }

    // MARK: - Availability

    func test_agentToolDefinitions_withoutFunctionCalling_exposesNoTools() throws {
        // Given
        let sut = makeViewModel(model: LLMModel(id: "no-tools"), pending: [imageAttachment()])

        // When
        let definitions = sut.agentToolDefinitions(for: try loadedState(sut))

        // Then
        XCTAssertTrue(definitions.isEmpty)
    }

    func test_agentToolDefinitions_nativeVision_omitsAnalysisButKeepsGeneration() throws {
        // Given
        let model = LLMModel(id: "native-vision", capabilities: [.functionCalling, .vision])
        let sut = makeViewModel(model: model, pending: [imageAttachment()])

        // When
        let names = try visualToolNames(sut)

        // Then
        XCTAssertEqual(names, ["generate_image"])
    }

    func test_agentToolDefinitions_nativeChatGeneration_omitsGenerationButKeepsAnalysis() throws {
        // Given
        let model = LLMModel(id: "native-image-chat", capabilities: [.functionCalling, .imageGeneration])
        let sut = makeViewModel(model: model, pending: [imageAttachment()])

        // When
        let names = try visualToolNames(sut)

        // Then
        XCTAssertEqual(names, ["analyze_images", "list_image_attachments"])
    }

    func test_agentToolDefinitions_dualNativeModel_omitsBothVisualTools() throws {
        // Given
        let model = LLMModel(id: "dual-native", capabilities: [.functionCalling, .vision, .imageGeneration])
        let sut = makeViewModel(model: model, pending: [imageAttachment()])

        // When
        let definitions = sut.agentToolDefinitions(for: try loadedState(sut))

        // Then
        XCTAssertTrue(try visualToolNames(sut).isEmpty)
        XCTAssertTrue(definitions.contains { $0.function.name == "get_current_datetime" })
    }

    func test_agentToolDefinitions_textModelWithImage_exposesBothSpecialists() throws {
        // Given
        let image = imageAttachment()
        let sut = makeViewModel(pending: [image])

        // When
        let definitions = sut.agentToolDefinitions(for: try loadedState(sut))
        let analysis = try XCTUnwrap(definitions.first { $0.function.name == "analyze_images" })

        // Then
        XCTAssertEqual(try visualToolNames(sut), ["analyze_images", "generate_image", "list_image_attachments"])
        XCTAssertNil(analysis.function.parameters.properties["attachment_ids"]?.items?.enum)
    }

    func test_agentToolDefinitions_withoutImage_exposesOnlyGeneration() throws {
        // Given
        let document = ChatMessage.Attachment(
            type: .pdf, fileName: "file.pdf", mimeType: "application/pdf", fileRelativePath: ""
        )
        let sut = makeViewModel(pending: [document])

        // When
        let names = try visualToolNames(sut)

        // Then
        XCTAssertEqual(names, ["generate_image"])
    }

    func test_agentToolDefinitions_noSpecialistDefaults_doesNotAutomaticallySelectModels() throws {
        // Given
        settings.setSelectedVisionModelId(nil)
        settings.setSelectedImageGenerationModelId(nil)
        let sut = makeViewModel(pending: [imageAttachment()])

        // When
        let names = try visualToolNames(sut)

        // Then
        XCTAssertTrue(names.isEmpty)
        XCTAssertEqual(try loadedState(sut).selectedModel, principal)
        XCTAssertNil(settings.getSelectedVisionModelId())
        XCTAssertNil(settings.getSelectedImageGenerationModelId())
    }

    func test_agentToolDefinitions_staleOrWrongCapabilityDefaults_doesNotFallBack() throws {
        // Given
        let sut = makeViewModel(pending: [imageAttachment()])
        let selections = [("missing-vision", "missing-generator"), (generator.id, vision.id)]

        // When / Then
        for (visionId, generationId) in selections {
            settings.setSelectedVisionModelId(visionId)
            settings.setSelectedImageGenerationModelId(generationId)
            XCTAssertTrue(try visualToolNames(sut).isEmpty)
        }
    }

    func test_makeLoadedState_specialistDefaults_keepsPrincipalAndCapturesCatalogScope() {
        // Given
        let sut = makeViewModel()

        // When
        let state = sut.makeLoadedState(models: [generator, vision, principal], pending: nil)

        // Then
        XCTAssertEqual(state.selectedModel, principal)
        XCTAssertEqual(state.modelCatalogScope, settings.getMCPAuthorizationScope())
        XCTAssertEqual(settings.getSelectedVisionModelId(), vision.id)
        XCTAssertEqual(settings.getSelectedImageGenerationModelId(), generator.id)
        XCTAssertNil(saveSelectedModel.savedModelId)
    }

    // MARK: - Helpers

    func makeViewModel(
        model: LLMModel? = nil,
        pending: [ChatMessage.Attachment] = [],
        conversation: Conversation? = nil,
        isPrivate: Bool = false,
        extraModels: [LLMModel] = []
    ) -> ChatViewModel {
        let selectedModel = model ?? principal
        let sut = ChatViewModel(
            isPrivateChat: isPrivate,
            state: .loaded(.init(
                conversation: conversation,
                messages: conversation?.messages ?? [],
                selectedModel: selectedModel,
                availableModels: [selectedModel, vision, generator] + extraModels,
                modelCatalogScope: settings.getMCPAuthorizationScope(),
                pendingAttachments: pending
            )),
            fetchModelsUseCase: MockFetchModelsUseCase(),
            prepareImageAttachmentUseCase: preparation,
            attachmentRepository: attachments,
            streamMessageUseCase: stream,
            generateImageUseCase: nativeGeneration,
            agentStreamUseCase: agent,
            webSearchUseCase: MockWebSearchUseCase(),
            saveConversationUseCase: save,
            getChatPreferencesUseCase: preferences,
            saveSelectedModelUseCase: saveSelectedModel,
            fetchMCPToolsUseCase: MockFetchMCPToolsUseCase(),
            settingsManager: settings,
            getUserProfileContextUseCase: MockGetUserProfileContextUseCase(),
            getMemoryContextUseCase: MockGetMemoryContextUseCase(),
            memoryManager: MockMemoryManager(),
            triggerHapticFeedbackUseCase: MockTriggerHapticFeedbackUseCase(),
            streamingBackgroundUseCase: background,
            notifyStreamingCompletedUseCase: MockNotifyStreamingCompletedUseCase(),
            compactConversationUseCase: MockCompactConversationUseCase(),
            imageToolChatRepository: ChatRepository(apiClient: apiClient, attachmentRepository: attachments),
            imageToolGenerationUseCase: specialistGeneration
        )
        viewModels.append(sut)
        return sut
    }

    func loadedState(_ sut: ChatViewModel) throws -> ChatViewModel.LoadedState {
        guard case .loaded(let state) = sut.state else {
            throw XCTUnwrapError.expectedLoadedState
        }
        return state
    }

    func visualToolNames(_ sut: ChatViewModel) throws -> Set<String> {
        Set(sut.agentToolDefinitions(for: try loadedState(sut)).map(\.function.name))
            .intersection(["analyze_images", "generate_image", "list_image_attachments"])
    }

    func sendMessage(_ sut: ChatViewModel, prompt: String = "Describe the images") async throws {
        sut.send(.inputChanged(prompt))
        sut.send(.sendTapped)
        let task = try XCTUnwrap(sut.streamTask)
        await task.value
    }

    func capturedRegistry() throws -> ToolRegistry {
        try XCTUnwrap(agent.receivedToolContext).toolRegistry
    }

    func authorizedInvocation(
        _ registry: ToolRegistry, name: String, arguments: String
    ) async throws -> ToolRegistry.AuthorizedInvocation {
        let call = ToolCall(id: UUID().uuidString, type: "function", function: .init(name: name, arguments: arguments))
        let outcomes = try await registry.resolveAuthorization(registry.makeAuthorizationPlan(for: [call]))
        guard case .authorized(let invocation) = try XCTUnwrap(outcomes.first) else {
            throw XCTUnwrapError.expectedAuthorizedInvocation
        }
        return invocation
    }

    func imageAttachment(conversationId: UUID? = nil, data: Data? = Data([1, 2, 3])) -> ChatMessage.Attachment {
        let id = UUID()
        return ChatMessage.Attachment(
            id: id, type: .image, fileName: "photo.jpg", mimeType: "image/jpeg",
            fileRelativePath: conversationId.map { "Attachments/\($0)/\(id).jpg" } ?? "",
            transientData: data
        )
    }

    func analysisArguments(ids: [UUID]) throws -> String {
        let encodedIds = try XCTUnwrap(String(data: JSONEncoder().encode(ids), encoding: .utf8))
        return "{\"question\":\"Compare these images\",\"attachment_ids\":\(encodedIds)}"
    }

    private enum XCTUnwrapError: Error {
        case expectedLoadedState
        case expectedAuthorizedInvocation
    }
}
