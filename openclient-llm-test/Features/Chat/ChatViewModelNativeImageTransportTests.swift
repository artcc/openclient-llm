//
//  ChatViewModelNativeImageTransportTests.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 10/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Observation
import XCTest
@testable import openclient_llm

@MainActor
final class ChatViewModelNativeImageTransportTests: XCTestCase {
    // MARK: - Properties

    private let settings = MockSettingsManager()
    private let save = MockSaveConversationUseCase()
    private let agent = MockAgentStreamUseCase()
    private let generation = MockGenerateImageUseCase()
    private var viewModels: [ChatViewModel] = []

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()
        guard URLProtocol.registerClass(NativeImageTransportURLProtocol.self) else {
            throw URLError(.unsupportedURL)
        }
        settings.serverBaseURL = "native-image-transport-test://original/v1"
        settings.apiKey = "original-test-key"
    }

    override func tearDown() async throws {
        for viewModel in viewModels {
            let task = viewModel.streamTask
            viewModel.send(.viewDisappeared)
            viewModel.errorDismissTask?.cancel()
            viewModel.mcpSettingsObservationTask?.cancel()
            viewModel.mcpDiscoveryTask?.cancel()
            await task?.value
            _ = await viewModel.persistenceTask?.value
        }
        viewModels = []
        URLProtocol.unregisterClass(NativeImageTransportURLProtocol.self)
        try await super.tearDown()
    }

    // MARK: - Tests

    func test_makeChatRepository_nativeImage_capturesSettingsForStreamAndAgent() async throws {
        // Given
        let sut = makeViewModel(model: LLMModel(id: "native", capabilities: [.imageGeneration]))
        let repository = sut.makeChatRepository(generatesImages: true)
        settings.serverBaseURL = "native-image-transport-test://replacement/v2"
        settings.apiKey = "replacement-test-key"

        // When
        for usesAgent in [false, true] {
            let request = try await capturedRequest(repository: repository, usesAgent: usesAgent)

            // Then
            XCTAssertEqual(request.url.absoluteString, "native-image-transport-test://original/v1/chat/completions")
            XCTAssertEqual(request.authorization, "Bearer original-test-key")
            XCTAssertEqual(request.method, "POST")
            XCTAssertEqual(request.timeoutInterval, 600)
            XCTAssertEqual(request.body.modalities, ["image", "text"])
            XCTAssertEqual(request.body.stream, !usesAgent)
            XCTAssertEqual(request.body.model, "native")
            XCTAssertNil(request.body.tools)
        }
    }

    func test_makeChatRepository_textOnly_preservesDefaultTimeoutAndOmitsModalities() async throws {
        // Given
        let sut = makeViewModel(model: LLMModel(id: "native"))
        let repository = sut.makeChatRepository(generatesImages: false)

        // When
        for usesAgent in [false, true] {
            let request = try await capturedRequest(repository: repository, usesAgent: usesAgent)

            // Then
            XCTAssertEqual(request.timeoutInterval, 60)
            XCTAssertNil(request.body.modalities)
            XCTAssertEqual(request.body.stream, !usesAgent)
        }
    }

    func test_send_nilUseCases_selectsNativeTransportUsingCurrentSettings() async throws {
        for usesAgent in [false, true] {
            // Given
            settings.serverBaseURL = "native-image-transport-test://original/v1"
            settings.apiKey = "original-test-key"
            let capabilities: [LLMModel.Capability] = usesAgent
                ? [.imageGeneration, .functionCalling] : [.imageGeneration]
            let sut = makeViewModel(model: LLMModel(id: "native", capabilities: capabilities))
            settings.serverBaseURL = "native-image-transport-test://current/v3"
            settings.apiKey = "current-test-key"

            // When
            sut.send(.inputChanged("Draw a cat"))
            sut.send(.sendTapped)
            let task = try XCTUnwrap(sut.streamTask)
            await task.value

            // Then
            let state = try loadedState(sut)
            let content = try XCTUnwrap(state.messages.last?.content)
            let request = try JSONDecoder().decode(NativeImageCapturedRequest.self, from: Data(content.utf8))
            XCTAssertEqual(request.url.absoluteString, "native-image-transport-test://current/v3/chat/completions")
            XCTAssertEqual(request.authorization, "Bearer current-test-key")
            XCTAssertEqual(request.timeoutInterval, 600)
            XCTAssertEqual(request.body.modalities, ["image", "text"])
            XCTAssertEqual(request.body.stream, !usesAgent)
            XCTAssertEqual(request.body.model, "native")
            if usesAgent {
                XCTAssertEqual(request.body.tools?.map(\.function.name), ["get_current_datetime"])
            } else {
                XCTAssertNil(request.body.tools)
            }
            XCTAssertEqual(generation.executeCallCount, 0)
            XCTAssertFalse(state.isStreaming)
            XCTAssertNil(state.errorMessage)
        }
    }

    func test_send_nativeImageWithoutTools_cancelDuringText_preservesImageAndPartialText() async throws {
        // Given
        let image = try XCTUnwrap(Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"))
        let (stream, continuation) = AsyncThrowingStream<StreamChunk, Error>.makeStream()
        defer { continuation.finish() }
        let sut = makeViewModel(
            model: LLMModel(id: "native", capabilities: [.imageGeneration]),
            stream: ControlledNativeImageStream(stream: stream),
            agent: agent
        )
        sut.send(.inputChanged("Draw a cat"))
        sut.send(.sendTapped)
        let task = try XCTUnwrap(sut.streamTask)
        let receivedPartialResponse = expectation(description: "Image and partial text published")
        Self.observePartialResponse(sut, expectation: receivedPartialResponse)

        // When
        continuation.yield(.image(image))
        continuation.yield(.token("Here is"))
        await fulfillment(of: [receivedPartialResponse], timeout: 2)
        let partial = try loadedState(sut)
        sut.send(.stopStreamingTapped)
        continuation.yield(.token(" text after cancellation"))
        continuation.finish()
        await task.value

        // Then
        let state = try loadedState(sut)
        XCTAssertTrue(partial.isStreaming)
        XCTAssertEqual(state.messages.last?.role, .assistant)
        XCTAssertEqual(state.messages.last?.content, "Here is")
        XCTAssertEqual(state.messages.last?.attachments, partial.messages.last?.attachments)
        XCTAssertEqual(state.messages.last?.attachments.count, 1)
        XCTAssertEqual(state.messages.last?.attachments.first?.transientData, image)
        XCTAssertEqual(state.messages.last?.attachments.first?.mimeType, "image/gif")
        XCTAssertFalse(state.isStreaming)
        XCTAssertNil(state.errorMessage)
        XCTAssertNil(sut.activeAssistantMessageId)
        XCTAssertEqual(agent.executeCallCount, 0)
        XCTAssertEqual(generation.executeCallCount, 0)
        XCTAssertEqual(save.executeCallCount, 0)
    }

    func test_inputBarSnapshot_imageModelNames_sanitizesControlsAndBoundsLengthWithoutChangingState() {
        // Given
        let names = [
            "analyze_images": " \u{202E}Vision\n\tModel\u{0000} ",
            "generate_image": "\u{2066}" + String(repeating: "x", count: 200) + "\u{2069}"
        ]
        var state = ChatViewModel.LoadedState(imageToolModelNames: names)

        // When
        let snapshot = ChatInputBarState(loadedState: state)
        state.imageToolModelNames["analyze_images"] = "\u{202E}\u{0000}\n\t"
        let emptyNameSnapshot = ChatInputBarState(loadedState: state)

        // Then
        XCTAssertEqual(snapshot.imageToolModelNames["analyze_images"], "Vision Model")
        XCTAssertEqual(snapshot.imageToolModelNames["generate_image"], String(repeating: "x", count: 160))
        XCTAssertEqual(emptyNameSnapshot.imageToolModelNames["analyze_images"], String(localized: "Image model"))
        XCTAssertEqual(state.imageToolModelNames["generate_image"], names["generate_image"])
        XCTAssertEqual(state.imageToolModelNames["analyze_images"], "\u{202E}\u{0000}\n\t")
    }

    // MARK: - Private

    private func makeViewModel(
        model: LLMModel,
        stream: StreamMessageUseCaseProtocol? = nil,
        agent: AgentStreamUseCaseProtocol? = nil
    ) -> ChatViewModel {
        let sut = ChatViewModel(
            isPrivateChat: true,
            state: .loaded(.init(
                selectedModel: model, availableModels: [model], modelCatalogScope: settings.getMCPAuthorizationScope()
            )),
            fetchModelsUseCase: MockFetchModelsUseCase(),
            prepareImageAttachmentUseCase: MockPrepareImageAttachmentUseCase(),
            attachmentRepository: MockAttachmentRepository(),
            streamMessageUseCase: stream,
            generateImageUseCase: generation,
            agentStreamUseCase: agent,
            webSearchUseCase: MockWebSearchUseCase(),
            saveConversationUseCase: save,
            getChatPreferencesUseCase: MockGetChatPreferencesUseCase(),
            saveSelectedModelUseCase: MockSaveSelectedModelUseCase(),
            fetchMCPToolsUseCase: MockFetchMCPToolsUseCase(),
            settingsManager: settings,
            triggerHapticFeedbackUseCase: MockTriggerHapticFeedbackUseCase(),
            streamingBackgroundUseCase: MockStreamingBackgroundUseCase(),
            notifyStreamingCompletedUseCase: MockNotifyStreamingCompletedUseCase(),
            compactConversationUseCase: MockCompactConversationUseCase()
        )
        viewModels.append(sut)
        return sut
    }

    private func loadedState(_ sut: ChatViewModel) throws -> ChatViewModel.LoadedState {
        guard case .loaded(let state) = sut.state else { throw URLError(.cannotParseResponse) }
        return state
    }

    private func capturedRequest(
        repository: ChatRepository, usesAgent: Bool
    ) async throws -> NativeImageCapturedRequest {
        let messages = [ChatMessage(role: .user, content: "Draw a cat")]
        var content = ""
        if usesAgent {
            let useCase = AgentStreamUseCase(repository: repository, chunkDelay: .zero)
            for try await event in useCase.execute(
                messages: messages, model: "native", parameters: .default, toolRegistry: ToolRegistry(tools: [])
            ) {
                if case .token(let text) = event { content += text }
            }
        } else {
            let useCase = StreamMessageUseCase(repository: repository)
            for try await chunk in useCase.execute(messages: messages, model: "native", parameters: .default) {
                if case .token(let text) = chunk { content += text }
            }
        }
        return try JSONDecoder().decode(NativeImageCapturedRequest.self, from: Data(content.utf8))
    }

    private static func observePartialResponse(_ sut: ChatViewModel, expectation: XCTestExpectation) {
        if case .loaded(let state) = sut.state,
           state.messages.last?.content == "Here is", state.messages.last?.attachments.count == 1 {
            expectation.fulfill()
            return
        }
        withObservationTracking {
            _ = sut.state
        } onChange: { [weak sut] in
            Task { @MainActor in
                guard let sut else { return }
                observePartialResponse(sut, expectation: expectation)
            }
        }
    }
}

private struct ControlledNativeImageStream: StreamMessageUseCaseProtocol {
    let stream: AsyncThrowingStream<StreamChunk, Error>

    func execute(
        messages: [ChatMessage], model: String, parameters: ModelParameters
    ) -> AsyncThrowingStream<StreamChunk, Error> {
        stream
    }
}

private struct NativeImageCapturedRequest: Codable, Sendable {
    let url: URL
    let method: String?
    let authorization: String?
    let timeoutInterval: TimeInterval
    let body: Body

    struct Body: Codable, Sendable {
        let model: String
        let stream: Bool
        let modalities: [String]?
        let tools: [ToolDefinition]?
    }
}

private final class NativeImageTransportURLProtocol: URLProtocol {
    // A test-only scheme cannot fall through to a real HTTP request if interception fails.
    override static func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "native-image-transport-test"
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let url = request.url else { throw URLError(.badURL) }
            let body = try JSONDecoder().decode(NativeImageCapturedRequest.Body.self, from: readBody())
            let captured = NativeImageCapturedRequest(
                url: url, method: request.httpMethod,
                authorization: request.value(forHTTPHeaderField: "Authorization"),
                timeoutInterval: request.timeoutInterval, body: body
            )
            // Echo the request through content instead of sharing mutable callback state.
            guard let content = String(data: try JSONEncoder().encode(captured), encoding: .utf8),
                  let encodedContent = String(data: try JSONEncoder().encode(content), encoding: .utf8) else {
                throw URLError(.cannotDecodeRawData)
            }
            let messageKey = body.stream ? "delta" : "message"
            let payload = """
            {"id":"transport","choices":[{"finish_reason":"stop","\(messageKey)":{
            "role":"assistant","content":\(encodedContent)}}]}
            """.replacingOccurrences(of: "\n", with: "")
            let contentType = body.stream ? "text/event-stream" : "application/json"
            guard let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": contentType]
            ) else { throw URLError(.badServerResponse) }
            let data = Data((body.stream ? "data: \(payload)\n\ndata: [DONE]\n\n" : payload).utf8)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private func readBody() throws -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { throw URLError(.cannotDecodeRawData) }
        stream.open()
        defer { stream.close() }
        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            guard count > 0 else { return body }
            body.append(contentsOf: buffer.prefix(count))
        }
    }
}
