//
//  AgentStreamUseCase+ToolResults.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 14/08/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

extension AgentStreamUseCase {
    func boundedToolResult(_ result: ToolCallResult, maximumCharacters: Int) -> ToolCallResult {
        if result.toolName.hasPrefix("mcp_") || result.toolName == "analyze_images" {
            return ToolCallResult(
                toolCallId: result.toolCallId,
                toolName: result.toolName,
                executionResult: ToolExecutionResult(
                    text: MCPDisplayText.wrappedToolResultForModel(
                        result.executionResult.text,
                        maximumBytes: maximumCharacters
                    ),
                    searchResults: result.executionResult.searchResults,
                    images: result.executionResult.images
                )
            )
        }
        let marker = "\n[Tool result truncated]"
        guard result.executionResult.text.utf8.count > maximumCharacters else { return result }
        guard maximumCharacters > 0 else {
            return ToolCallResult(
                toolCallId: result.toolCallId,
                toolName: result.toolName,
                executionResult: ToolExecutionResult(
                    text: "",
                    searchResults: result.executionResult.searchResults,
                    images: result.executionResult.images
                )
            )
        }
        let contentLimit = max(0, maximumCharacters - marker.utf8.count)
        let suffix = maximumCharacters >= marker.utf8.count ? marker : ""
        return ToolCallResult(
            toolCallId: result.toolCallId,
            toolName: result.toolName,
            executionResult: ToolExecutionResult(
                text: utf8Prefix(result.executionResult.text, maximumBytes: contentLimit) + suffix,
                searchResults: result.executionResult.searchResults,
                images: result.executionResult.images
            )
        )
    }

    func utf8Prefix(_ text: String, maximumBytes: Int) -> String {
        var result = ""
        var byteCount = 0
        for character in text {
            let bytes = String(character).utf8.count
            guard byteCount + bytes <= maximumBytes else { break }
            result.append(character)
            byteCount += bytes
        }
        return result
    }
}
