//
//  ChatRepository.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

protocol ChatRepositoryProtocol: Sendable {
    func sendMessage(
        messages: [ChatMessage],
        model: String,
        parameters: ModelParameters
    ) async throws -> (String, TokenUsage?)
    func streamMessage(
        messages: [ChatMessage],
        model: String,
        parameters: ModelParameters
    ) -> AsyncThrowingStream<StreamChunk, Error>
    func agentCompletion(
        messages: [ChatMessage],
        model: String,
        parameters: ModelParameters,
        tools: [ToolDefinition]?
    ) async throws -> ChatCompletionResponse
}

enum StreamChunk: Sendable {
    case token(String)
    case reasoning(String)
    case usage(TokenUsage)
    case image(Data)
}

struct ChatRepository: ChatRepositoryProtocol {
    // MARK: - Properties

    private let apiClient: APIClientProtocol
    private let attachmentRepository: AttachmentRepositoryProtocol
    private let responseModalities: [String]?
    private let requestTimeoutInterval: TimeInterval

    // MARK: - Init

    init(
        apiClient: APIClientProtocol = APIClient(),
        attachmentRepository: AttachmentRepositoryProtocol = AttachmentRepository(),
        responseModalities: [String]? = nil,
        requestTimeoutInterval: TimeInterval = 60
    ) {
        self.apiClient = apiClient
        self.attachmentRepository = attachmentRepository
        self.responseModalities = responseModalities
        self.requestTimeoutInterval = requestTimeoutInterval
    }

    // MARK: - Public

    func sendMessage(
        messages: [ChatMessage],
        model: String,
        parameters: ModelParameters
    ) async throws -> (String, TokenUsage?) {
        LogManager.info("sendMessage model=\(model) messages=\(messages.count)")
        let request = ChatCompletionRequest(
            model: model,
            messages: messages.map { buildCompletionMessage($0) },
            stream: false,
            temperature: parameters.temperature,
            maxTokens: parameters.maxTokens,
            topP: parameters.topP,
            streamOptions: nil,
            modalities: nil,
            tools: nil,
            toolChoice: nil
        )

        let response: ChatCompletionResponse = try await apiClient.request(
            endpoint: "chat/completions",
            method: .post,
            body: request
        )

        guard let content = response.choices.first?.message.content else {
            LogManager.error("sendMessage: no content in response")
            throw APIError.invalidResponse
        }

        let tokenUsage = response.usage.map {
            TokenUsage(
                promptTokens: $0.promptTokens ?? 0,
                completionTokens: $0.completionTokens ?? 0,
                totalTokens: $0.totalTokens ?? 0
            )
        }
        LogManager.success("sendMessage done \(content.count) chars tokens=\(tokenUsage?.totalTokens ?? 0)")
        return (content, tokenUsage)
    }

    func streamMessage(
        messages: [ChatMessage],
        model: String,
        parameters: ModelParameters
    ) -> AsyncThrowingStream<StreamChunk, Error> {
        LogManager.info("streamMessage model=\(model) messages=\(messages.count)")
        let request = ChatCompletionRequest(
            model: model,
            messages: messages.map { buildCompletionMessage($0) },
            stream: true,
            temperature: parameters.temperature,
            maxTokens: parameters.maxTokens,
            topP: parameters.topP,
            streamOptions: ChatStreamOptions(includeUsage: true),
            modalities: responseModalities,
            tools: nil,
            toolChoice: nil
        )

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dataStream = apiClient.streamRequest(endpoint: "chat/completions", body: request)

        return AsyncThrowingStream { continuation in
            let task = Task {
                await runStream(dataStream: dataStream, decoder: decoder, continuation: continuation)
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func agentCompletion(
        messages: [ChatMessage],
        model: String,
        parameters: ModelParameters,
        tools: [ToolDefinition]?
    ) async throws -> ChatCompletionResponse {
        LogManager.info("agentCompletion model=\(model) messages=\(messages.count) tools=\(tools?.count ?? 0)")
        let request = ChatCompletionRequest(
            model: model,
            messages: messages.map { buildCompletionMessage($0) },
            stream: false,
            temperature: parameters.temperature,
            maxTokens: parameters.maxTokens,
            topP: parameters.topP,
            streamOptions: nil,
            modalities: responseModalities,
            tools: tools,
            toolChoice: tools != nil ? "auto" : nil
        )
        let response: ChatCompletionResponse = try await apiClient.request(
            endpoint: "chat/completions",
            method: .post,
            body: request,
            timeoutInterval: requestTimeoutInterval
        )
        LogManager.success("agentCompletion done finishReason=\(response.choices.first?.finishReason ?? "nil")")
        return response
    }
}

// MARK: - Private

private extension ChatRepository {
    func runStream(
        dataStream: AsyncThrowingStream<Data, Error>,
        decoder: JSONDecoder,
        continuation: AsyncThrowingStream<StreamChunk, Error>.Continuation
    ) async {
        do {
            var totalChars = 0
            var imageChunks = 0
            for try await data in dataStream {
                guard !Task.isCancelled else { break }
                let chunk: ChatCompletionStreamResponse
                do {
                    chunk = try decoder.decode(ChatCompletionStreamResponse.self, from: data)
                } catch {
                    let preview = String(data: data, encoding: .utf8)?.prefix(200) ?? "<non-utf8>"
                    LogManager.warning("streamMessage skipping undecodable chunk: \(error) — \(preview)")
                    continue
                }
                if let content = chunk.choices.first?.delta.content {
                    totalChars += content.count
                    continuation.yield(.token(content))
                }
                if let reasoning = chunk.choices.first?.delta.reasoningContent {
                    continuation.yield(.reasoning(reasoning))
                }
                if let images = chunk.choices.first?.delta.images {
                    for item in images {
                        let image = try GeneratedImageDecoder.decode(dataURL: item.imageUrl.url)
                        imageChunks += 1
                        LogManager.debug("streamMessage image chunk \(imageChunks) \(image.data.count) bytes")
                        continuation.yield(.image(image.data))
                    }
                }
                if let usage = chunk.usage {
                    let tokenUsage = TokenUsage(
                        promptTokens: usage.promptTokens ?? 0,
                        completionTokens: usage.completionTokens ?? 0,
                        totalTokens: usage.totalTokens ?? 0
                    )
                    let usageLog = "prompt=\(tokenUsage.promptTokens) completion=\(tokenUsage.completionTokens)"
                    LogManager.debug("streamMessage usage \(usageLog) total=\(tokenUsage.totalTokens)")
                    continuation.yield(.usage(tokenUsage))
                }
            }
            LogManager.success("streamMessage finished totalChars=\(totalChars) imageChunks=\(imageChunks)")
            continuation.finish()
        } catch {
            LogManager.error("streamMessage decoding/stream error: \(error)")
            continuation.finish(throwing: error)
        }
    }

    func buildCompletionMessage(_ message: ChatMessage) -> ChatCompletionMessage {
        // Tool result message: role "tool" with tool_call_id and name
        if message.role == .tool {
            return ChatCompletionMessage(
                role: "tool",
                content: .text(message.content),
                toolCallId: message.toolCallId,
                name: message.toolName
            )
        }

        // Assistant message with tool_calls: content is null
        if message.role == .assistant, let toolCalls = message.toolCalls, !toolCalls.isEmpty {
            return ChatCompletionMessage(
                role: "assistant",
                content: .none,
                toolCallId: nil,
                toolCalls: toolCalls
            )
        }

        if message.attachments.isEmpty {
            return ChatCompletionMessage(
                role: message.role.rawValue,
                content: .text(message.content)
            )
        }

        var parts: [ContentPart] = []

        if !message.content.isEmpty {
            parts.append(.text(message.content))
        }

        for attachment in message.attachments {
            guard let data = attachment.transientData ?? (try? attachmentRepository.load(attachment: attachment)) else {
                LogManager.warning("buildCompletionMessage: could not load attachment \(attachment.id) — skipping")
                continue
            }
            switch attachment.type {
            case .image:
                guard data.count <= ImageAttachmentConstraints.maximumBytes else {
                    LogManager.warning("buildCompletionMessage: image exceeds size limit — skipping")
                    continue
                }
                let base64 = data.base64EncodedString()
                parts.append(.imageBase64(base64, mimeType: attachment.mimeType))
            case .pdf:
                let pdfText = PDFTextExtractor.extract(from: data)
                if !pdfText.isEmpty {
                    parts.append(.text("[Document: \(attachment.fileName)]\n\(pdfText)"))
                }
            }
        }

        return ChatCompletionMessage(
            role: message.role.rawValue,
            content: .multimodal(parts)
        )
    }
}
