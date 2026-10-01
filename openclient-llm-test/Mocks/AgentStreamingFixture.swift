//
//  AgentStreamingFixture.swift
//  openclient-llm-test
//
//  Created by Arturo Carretero Calvo on 01/10/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import Foundation

enum AgentStreamingFixture {
    static func chunk(
        content: String? = nil,
        reasoning: String? = nil,
        calls: [[String: Any]]? = nil,
        finish: String? = nil,
        usage: [String: Int]? = nil
    ) throws -> Data {
        var delta: [String: Any] = [:]
        delta["content"] = content
        delta["reasoning_content"] = reasoning
        delta["tool_calls"] = calls
        var choice: [String: Any] = ["index": 0, "delta": delta]
        choice["finish_reason"] = finish
        var payload: [String: Any] = ["id": "test-stream", "choices": usage == nil ? [choice] : []]
        payload["usage"] = usage
        return try JSONSerialization.data(withJSONObject: payload)
    }

    static func call(
        index: Int = 0,
        id: String? = nil,
        name: String? = nil,
        arguments: String = ""
    ) -> [String: Any] {
        var function: [String: Any] = ["arguments": arguments]
        function["name"] = name
        var call: [String: Any] = ["index": index, "function": function]
        call["id"] = id
        if id != nil { call["type"] = "function" }
        return call
    }
}
