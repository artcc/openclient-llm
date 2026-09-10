---
description: "Use when implementing agent mode, tool/function calling, building the agentic loop, registering tools, parsing tool_calls responses, or showing tool execution UI in chat."
applyTo: "**/*.swift"
---

# Agent Mode — Tool Calling Integration

## Overview

Agent mode allows the LLM to call **tools** (functions) that the app executes locally, then returns results to the model for continued reasoning. This enables multi-step workflows where the model can search the web, perform calculations, or interact with external services.

## OpenAI-Compatible Tool Calling Protocol

LiteLLM exposes the standard OpenAI tool calling format. The protocol works identically whether the backend is OpenAI, Anthropic, Ollama, or any other provider.

### Tool Definition Format

Tools are defined as JSON in the `tools` array of the chat completions request:

```json
{
  "model": "gpt-4",
  "messages": [...],
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "web_search",
        "description": "Search the web for current information",
        "parameters": {
          "type": "object",
          "properties": {
            "query": {
              "type": "string",
              "description": "The search query"
            }
          },
          "required": ["query"]
        }
      }
    }
  ],
  "tool_choice": "auto"
}
```

### `tool_choice` Values

| Value | Behavior |
|-------|----------|
| `"auto"` | Model decides whether to call tools (default) |
| `"none"` | Model will not call any tools |
| `"required"` | Model must call at least one tool |
| `{"type": "function", "function": {"name": "..."}}` | Force a specific tool |

## The Agentic Loop

The core of agent mode is a **request → tool_calls → execute → result → continue** loop:

```
┌─────────────────────────────────────────────────────────┐
│ 1. Send messages + tools to /chat/completions           │
│                                                         │
│ 2. Response has finish_reason = "tool_calls"?           │
│    ├── YES → Parse tool_calls, execute each tool        │
│    │         Append assistant message (with tool_calls) │
│    │         Append tool result messages (role: "tool")  │
│    │         → Go back to step 1                        │
│    └── NO  → finish_reason = "stop"                     │
│              Display final response to user             │
└─────────────────────────────────────────────────────────┘
```

### Step-by-Step

**Step 1 — Send request with tools**

```json
POST /chat/completions
{
  "model": "gpt-4",
  "messages": [
    {"role": "user", "content": "What's the latest news about Swift?"}
  ],
  "tools": [/* tool definitions */],
  "tool_choice": "auto"
}
```

**Step 2 — Model responds with tool_calls**

```json
{
  "choices": [{
    "finish_reason": "tool_calls",
    "message": {
      "role": "assistant",
      "content": null,
      "tool_calls": [
        {
          "id": "call_abc123",
          "type": "function",
          "function": {
            "name": "web_search",
            "arguments": "{\"query\": \"Swift programming language latest news 2026\"}"
          }
        }
      ]
    }
  }]
}
```

Key fields:
- `finish_reason`: `"tool_calls"` indicates the model wants to call tools (not `"stop"`)
- `tool_calls[].id`: Unique ID that must be referenced in the tool result
- `tool_calls[].function.name`: Which tool to execute
- `tool_calls[].function.arguments`: JSON string with arguments (must be parsed)

**Step 3 — Execute tools and send results back**

Append the assistant message (with tool_calls) and tool results to the conversation:

```json
POST /chat/completions
{
  "model": "gpt-4",
  "messages": [
    {"role": "user", "content": "What's the latest news about Swift?"},
    {
      "role": "assistant",
      "content": null,
      "tool_calls": [
        {
          "id": "call_abc123",
          "type": "function",
          "function": {
            "name": "web_search",
            "arguments": "{\"query\": \"Swift programming language latest news 2026\"}"
          }
        }
      ]
    },
    {
      "role": "tool",
      "tool_call_id": "call_abc123",
      "name": "web_search",
      "content": "1. Swift 6.1 released with improved concurrency... 2. ..."
    }
  ],
  "tools": [/* same tool definitions */]
}
```

**Step 4 — Model generates final response (or calls more tools)**

```json
{
  "choices": [{
    "finish_reason": "stop",
    "message": {
      "role": "assistant",
      "content": "Here are the latest news about Swift:\n\n1. Swift 6.1..."
    }
  }]
}
```

If `finish_reason` is `"tool_calls"` again, repeat steps 2-3. If `"stop"`, display the response.

### Parallel Tool Calls

Some models can request multiple tool calls in a single response:

```json
"tool_calls": [
  {"id": "call_1", "function": {"name": "web_search", "arguments": "..."}},
  {"id": "call_2", "function": {"name": "web_search", "arguments": "..."}}
]
```

- `AgentStreamUseCase` executes accepted calls concurrently with a throwing task group, then restores model-request order when constructing tool messages.
- Send ALL results back in one request, each with its matching `tool_call_id`
- The current loop does not consult `supports_parallel_function_calling`; it concurrently executes multiple calls whenever the model returns them. Treat that as current behavior when changing capability handling.

### Loop Safety

- **Maximum iterations**: Cap the loop at 15 iterations to prevent infinite loops
- **Tool-call budget**: Cap the total number of calls at 20 and a single tool round at 8 calls.
- **Final-response round**: On the fifteenth iteration, after exhausting the total tool-call budget, or after rejecting excess calls from a round, send the next request without tools to force a final response.
- **Tool-result budget**: Rebuild the request context after every tool round and bound each result from the remaining input budget so tool output cannot consume the final-response space.
- **Continuous context**: Preserve the latest complete user turn and its assistant/tool messages atomically; never skip a recent turn to include an older one.
- **Transcript persistence**: Emit and persist every assistant `tool_calls` message and matching tool result before continuing the loop.
- **Timeout**: The base active-time limit is 300 seconds plus `AgentToolContext.additionalExecutionTime` (default `.zero`).
  `ChatViewModel` adds 600 seconds when the principal supports native image generation or the turn's initial registry
  advertises `generate_image`, for 900 seconds total. Vision-only delegation does not add this allowance.
  Pause the timer during user authorization.
- **User cancellation**: Allow the user to stop the loop at any point
- **Error in tool execution**: Return error message as tool content, let the model handle it

## Model Compatibility

### Checking Support

The `GET /model/info` endpoint provides capability flags:

```json
{
  "model_info": {
    "supports_function_calling": true,
    "supports_parallel_function_calling": true
  }
}
```

- Route every message for a model with `supports_function_calling: true` through `AgentStreamUseCase`; agent routing is automatic and is not controlled by a separate agent-mode toggle.
- Preserve `supports_parallel_function_calling` as model metadata. The current agent loop does not use it to gate concurrent local execution.
- Models without function calling use regular streaming. The web-search control is unavailable for those models.

### Provider Notes

| Provider | Tool Calling | Parallel | Notes |
|----------|-------------|----------|-------|
| OpenAI (GPT-4, GPT-4o) | ✅ | ✅ | Full support |
| Anthropic (Claude 3.5+) | ✅ | ✅ | Uses OpenAI format via LiteLLM |
| Ollama (Llama 3.1+, Qwen 2.5+) | ✅ | ❌ | Depends on model; check model_info |
| Groq | ✅ | ✅ | Full support |
| Mistral | ✅ | ✅ | Full support |

LiteLLM Ollama models must use the `ollama_chat/<model>` adapter for agent routing. The legacy `ollama/<model>` adapter
forces JSON output through `/api/generate`; the model repository removes `.functionCalling` for that route so regular chat
streaming is used instead.

## Implementation Architecture

### Models

```swift
// Extend the existing ChatMessage and API models

// Tool call in assistant response
struct ToolCall: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let type: String  // Always "function"
    let function: ToolCallFunction
}

struct ToolCallFunction: Codable, Sendable, Equatable {
    let name: String
    let arguments: String  // JSON string, must be parsed
}

// Tool result message (role: "tool")
// Extend ChatMessage.Role to include .tool
// Add toolCallId property to ChatMessage for role == .tool
// Add toolCalls property to ChatMessage for assistant messages with tool calls
```

### Tool Registry

```swift
// Shared/Features/Chat/Models/ChatTool.swift

nonisolated struct ToolExecutionResult: Sendable {
    let text: String
    let searchResults: [LiteLLMSearchResult]?
    let images: [GeneratedImage]

    init(text: String, searchResults: [LiteLLMSearchResult]? = nil, images: [GeneratedImage] = []) {
        self.text = text
        self.searchResults = searchResults
        self.images = images
    }
}

protocol ChatToolProtocol: Sendable {
    var definition: ToolDefinition { get }
    var isAvailableForAdvertisement: Bool { get }
    func execute(arguments: String) async throws -> ToolExecutionResult
}

extension ChatToolProtocol {
    var isAvailableForAdvertisement: Bool { true }
}

struct ToolDefinition: Codable, Sendable {
    let type: String  // "function"
    let function: ToolFunctionDefinition
}

struct ToolFunctionDefinition: Codable, Sendable {
    let name: String
    let description: String
    let parameters: ToolParameters
}
```

The default registry always includes `get_current_datetime`. Outside Private Chat it also includes `save_memory` and `delete_memory`. It includes `web_search` only while web search is enabled. When MCP tools are configured on the LiteLLM server and enabled by the user, each enabled tool is wrapped in an `MCPTool` instance (conforming to `ChatToolProtocol`) and added to the registry. `ToolRegistry.execute` returns an "Unknown tool" result rather than throwing when a name is not registered.

`ToolRegistry.definitions` filters all tools through `isAvailableForAdvertisement` on every access, in addition to MCP
availability checks. Image tools are conditionally added by `ChatViewModel+ImageTools`; their availability is not static
for the lifetime of a turn.

### Image And Vision Delegation

- Models has an **Image and Vision** section with independent optional `Vision` and `Image Generation` defaults,
  persisted as `selectedVisionModelId` and `selectedImageGenerationModelId`. Neither changes the principal chat model.
- `None` disables delegation for that role only. Missing or ineligible selections remain stored and visible as unavailable;
  never silently choose another specialist or another transport. A failed native operation does not trigger delegation.
- Vision specialists need `.vision` and a chat-compatible mode (`.chat`, `.completion`, or `.unknown`). Image specialists
  are dedicated `.imageGeneration` models or chat-compatible models with `.imageGeneration` capability.
- One dual-capability chat model can be selected for both roles. The defaults are independent, not mutually exclusive.
- Prioritize each native capability independently. `supportsNativeVision` checks `.vision`;
  `supportsNativeImageGeneration` checks dedicated image mode or `.imageGeneration` capability.
- LiteLLM `supported_output_modalities` containing `image` adds generation capability without changing the model's mode.
  Vision alone never implies generation support; missing output metadata does not infer a dual-capability model.

| Tool | Conditions for advertisement |
|---|---|
| `analyze_images` | Principal has `.functionCalling`, lacks native vision, a selected eligible vision specialist is present in the current catalog, and the conversation/turn has image attachments. |
| `generate_image` | Principal has `.functionCalling`, lacks native image generation, and a selected eligible dedicated or chat image specialist is present in the current catalog. No source attachment is required. |

Models without function calling never receive these tools. A principal with both native capabilities receives neither,
even when specialist defaults are configured. Delegation is automatic once configured, without MCP approval prompts;
the Models section warns that additional provider requests may incur costs.

### Image References And Context

- Keep original attachment UUIDs, metadata, and data in conversation state and normal persistence. Delegation does not
  replace stored images with descriptions or remove them from the visible conversation.
- For principals without native vision, `ImageAttachmentContext.messagesForModel` projects image attachments into textual
  `image_attachment_ids` references. Only canonical UUIDs enter this reference JSON, never names, paths, MIME types,
  URLs, or bytes. References explicitly distinguish uninspected images from actual analysis results.
- Apply the projection across history, including earlier user and assistant images, not just the latest user message.
  Use projected messages before context budgeting/usage estimation and before automatic compaction. Native-vision
  requests retain multimodal attachments; PDF text extraction stays on its existing path.
- Build the tool's attachment inventory from original history before request budgeting or compaction drops old turns.
  The `attachment_ids` item enum lists eligible historical image UUIDs, so earlier images remain addressable even when
  their messages no longer fit in the request. Pending attachments are included when estimating definitions in the UI.
- Compaction instructions preserve relevant UUIDs exactly and distinguish findings from uninspected references. Persist
  original history, not the model-only projection; references alone must never be treated as visual evidence.

### Image Tool Contracts

- `analyze_images` accepts a nonblank `question` of 1 to 4000 characters and 1 to 4 distinct `attachment_ids`; JSON arguments
  are limited to 64 KiB. Each UUID must uniquely resolve to an image from the captured conversation inventory, not a URL,
  arbitrary file path, or PDF. Persisted paths are checked against the conversation; transient data is also supported.
- Load and prepare each selected image through the existing attachment pipeline. Each prepared image must be nonempty,
  at most 5 MB (`ImageAttachmentConstraints.maximumBytes`), and JPEG, PNG, GIF, or WebP. Preparation retains the UUID.
- Analysis sends only a specialist system instruction, the question, and prepared images through `sendMessage`, without
  tools or a recursive agent loop. Output is capped at 2048 tokens and wrapped as untrusted analysis/OCR within 16000
  bytes before the agent's own remaining-budget bound. Image content and OCR must never become tool instructions.
- `generate_image` accepts only a nonblank text `prompt` of 1 to 8000 characters within a 64 KiB JSON argument limit.
  It generates one new image, without source attachments or editing. Reuse one `GenerateImageTool` instance across
  all rounds of the user turn and reserve its single generation attempt before the first suspension. A failed request
  still consumes the attempt because it may have incurred a charge; do not retry or switch specialists in that turn.
- After an attempt, `generate_image` is no longer advertised and repeated execution is rejected. Argument rejection before
  reservation does not issue a generation request. Dedicated specialists use `GenerateImageUseCase`; chat specialists use
  `GenerateChatImageUseCase`, which returns the first native image and never invokes tools recursively.
- Both tools check cancellation and availability before execution, around preparation where applicable, and after the
  specialist request, including failure paths. A stale response must not be published as a successful result.
- Availability captures the principal, specialist, and model-catalog authorization scope, then rechecks current selected
  IDs, conversation identity, catalog presence/eligibility, principal capabilities, and endpoint/credential scope.
  Specialist API clients capture
  the endpoint and credential pair rather than rereading mutable settings during requests. The loop's
  `isConfigurationCurrent` check and server-change cancellation provide an additional boundary against cross-endpoint data.

### Generated Image Delivery

- `ToolExecutionResult.images` is a typed, out-of-band `[GeneratedImage]` channel. Return only bounded textual status or
  analysis to the principal; never embed generated image bytes, base64, or data URLs in tool text, hidden tool transcripts,
  or model-facing tool results. Text truncation, including a zero-byte budget and untrusted-result wrapping, preserves images.
- Emit `.generatedImage(GeneratedImage)` as soon as a tool returns, before collecting sibling task-group results, so a
  later sibling failure cannot discard an already completed image. Native final chat images use the same typed event.
  Keep legacy `.image(Data)` support; typed delivery preserves the actual decoded MIME type.
- Attach images to the visible assistant message, not hidden tool-call messages. Checkpoint normal conversation persistence
  after every image event and `.transcriptAppended`, without waiting for final text. Image-only answers remain presentable,
  and already received attachments survive subsequent failure or cancellation. Private Chat retains them only in memory.
- The loop continues with the textual tool result to produce the principal's response. Do not invent image URLs or claim
  the principal inspected a generated image merely because generation succeeded.
- `.usage` aggregates only principal completion usage; `.promptUsage` calibrates the principal context. Specialist analysis
  usage and specialist generation usage are not added to that model's tokens or priced as its consumption. Additional
  provider charges can exist without being represented by the principal's usage counters.

### Agentic UseCase

```swift
// Shared/Features/Chat/UseCases/AgentStreamUseCase.swift

nonisolated struct AgentToolContext: Sendable {
    let toolRegistry: ToolRegistry
    let additionalExecutionTime: Duration
    let isConfigurationCurrent: @MainActor @Sendable () -> Bool

    init(
        toolRegistry: ToolRegistry,
        additionalExecutionTime: Duration = .zero,
        isConfigurationCurrent: @escaping @MainActor @Sendable () -> Bool = { true }
    ) {
        self.toolRegistry = toolRegistry
        self.additionalExecutionTime = additionalExecutionTime
        self.isConfigurationCurrent = isConfigurationCurrent
    }
}

protocol AgentStreamUseCaseProtocol: Sendable {
    func execute(
        messages: [ChatMessage],
        model: String,
        parameters: ModelParameters,
        contextWindowTokens: Int?,
        toolContext: AgentToolContext
    ) -> AsyncThrowingStream<AgentEvent, Error>
}

enum AgentEvent: Sendable {
    case token(String)
    case reasoning(String)
    case toolCallStarted(ToolCall)
    case toolCallCompleted(toolCallId: String, result: String, searchResults: [LiteLLMSearchResult]?)
    case transcriptAppended([ChatMessage])
    case usage(TokenUsage)
    case promptUsage(Int?)
    case image(Data)
    case generatedImage(GeneratedImage)
    case completed
}
```

The use case manages non-streaming completion requests for the full loop, then emits final content and reasoning in locally
paced, adaptively sized chunks for the existing streaming UI. Chunk count bounds requested pacing sleeps to approximately six
seconds per reasoning or answer field, and the request timeout pauses once valid final content has arrived. Failures terminate
the `AsyncThrowingStream`; there is no `.error` event. Assistant
tool-call messages and matching tool messages are emitted through `.transcriptAppended` and persisted before the next round.

Agent transcript messages remain in `ChatViewModel` for context and persistence, but presentation snapshots must exclude
`.tool` messages and hidden assistant tool-call messages. Never retain raw tool-result payloads in SwiftUI view values.

### ViewModel Integration

`ChatViewModel.streamWithWebSearch` uses `AgentStreamUseCase` whenever the selected model has `.functionCalling`, whether or not web search is enabled. It uses `StreamMessageUseCase` only for models without that capability. Web search changes the registry contents; it does not select agent routing.

## Streaming Considerations

Tool calling and streaming can interact in two ways:

### Current Behavior

- Agent rounds use non-streaming chat completions.
- Final content and reasoning are chunked locally into `AgentEvent` values.
- Tools remain present after a normal tool round, allowing multiple rounds. They are omitted only when forcing a final response because of iteration or tool-call safeguards, or when an empty/`{}` model response requires a final retry.

### Streaming Tool Calls (Advanced)

- LiteLLM streams tool call deltas: `delta.tool_calls[0].function.arguments` builds up incrementally
- Must accumulate argument fragments before parsing JSON
- More complex but provides real-time feedback

Do not implement streamed tool-call deltas unless the repository and event contract are deliberately changed and covered by tests.

## UI Design

### Automatic Agent Routing

- There is no separate Tools or Agent toggle.
- Function-calling models automatically receive the default registry.
- The globe control independently adds or removes `web_search` and requires both a configured search tool and a function-calling model.

### Tool Execution Feedback

During an agentic loop, show the user what's happening:

```
┌─────────────────────────────────────────────┐
│ 🔍 Searching the web...                     │
│    "Swift programming latest news 2026"     │
│ ✅ Found 5 results                          │
│                                              │
│ 🤖 Generating response...                   │
│    Based on the search results, here are... │
└─────────────────────────────────────────────┘
```

- Show each tool call as a collapsible step in the message
- Use icons: 🔍 for search, ⚙️ for tools, ✅ for completed
- Allow expanding to see tool arguments and results
- Show a "thinking" indicator during each loop iteration

### Message Display

- Assistant messages with `tool_calls` should show a "Used tools" indicator
- Tool result messages are internal — don't display them directly, but show a summary
- The final assistant message displays normally with the grounded response

## Conversation Persistence

When persisting conversations with tool calling:

- Store `tool_calls` array in assistant messages (already `Codable`)
- Store tool result messages with `role: "tool"` and `tool_call_id`
- On reload, the full message history (including tool results) must be preserved
- Do NOT resend tools array when loading historical conversations (no new tool calls on old messages)

## Error Handling

- **Invalid JSON in arguments**: Return error to model as tool result, let it retry
- **Tool execution failure**: Return error description as tool content
- **Model doesn't support tools**: Fall back to regular chat (no tools parameter)
- **Loop stuck**: The final iteration omits tools; another tool-call response throws `AgentStreamError.iterationLimitReached`, while an invalid forced-final response throws `.invalidResponse`.
- **Network error during tool execution**: Show error, allow retry
- **Unknown tool name**: Return "Unknown tool" as result, model can self-correct

## Security

- **Argument validation**: Parse and validate tool arguments before execution
- **No arbitrary code execution**: Tools are predefined, no dynamic tool loading
- **Rate limiting**: Apply rate limits to tool executions (especially web search)
- **Content sanitization**: Sanitize tool results before injecting into messages
- **Tool scope**: Function-calling models receive built-in datetime and, outside Private Chat, memory tools automatically. Web search remains explicit opt-in through its toggle.
- **Image scope**: Specialist defaults authorize only the eligible image tools described above; preserve native priority,
  per-turn generation limits, captured configuration, UUID-only analysis inputs, and untrusted-result boundaries.

## Relationship with Web Browsing

Web search (`web_search`) is the **first and primary tool** in the agent system:

- A model with `.functionCalling` always uses the agent loop. When web search is ON, `web_search` joins the default registry and executes through `/v1/search/{search_tool_name}`.
- Web search cannot be enabled unless the model has `.functionCalling` and a search tool name is configured; an unavailable globe is shown in red.
- When web search is OFF, function-calling models still use the agent loop with datetime, eligible memory/image tools,
  and enabled MCP tools. Models without `.functionCalling` use regular streaming.

## MCP Tools

MCP (Model Context Protocol) tools are external tools provided by MCP servers configured on the user's LiteLLM backend. They are discovered, persisted, and executed through a dedicated client-side pipeline that integrates transparently with the agent loop.

### Discovery

- `FetchMCPToolsUseCase.execute()` never throws and returns an `MCPDiscoveryResult`. It calls `GET /v1/mcp/server`, then concurrently calls `GET /mcp-rest/tools/list?server_id=X` for each server using one captured endpoint/credential pair.
- Discovered tools are stored in `ChatViewModel.LoadedState.availableMCPTools`. MCP discovery starts after the initial model state is available and can be refreshed independently.
- A top-level failure returns an empty result with an error. Partial failures retain prior tools for management visibility but mark their servers failed, so those tools are neither configurable nor advertised until a refresh succeeds.

### Tool Definition Conversion

Each supported `MCPToolInfo` is wrapped in an `MCPTool` that conforms to `ChatToolProtocol`. `MCPTool.toolParameters(from:)` converts the recursive `MCPJSONSchema` into `ToolParameters`:

- Object-root schemas are forwarded intact, including provider-specific annotations and standard constraints such as
  defaults, numeric bounds, lengths, and unions.
- The decoded structural subset is validated locally before authorization and execution; the MCP server remains
  authoritative for constraints the client does not interpret.
- A malformed schema, provider-specific non-object placeholder, or non-object root remains visible for management but is
  not advertised or executable.

### Execution

- `MCPTool.execute(arguments:)` delegates to `MCPRepository.executeTool()` → `APIClient.callMCPTool()` → `POST /mcp-rest/tools/call`.
- The request body includes `server_id`, `name` (the original un-prefixed tool name), and `arguments` parsed from the JSON string the LLM produced.
- The response `content` items are joined and returned as a `ToolExecutionResult`.

### User Management

- An MCP antenna icon next to the web search globe opens the `MCPToolsSheet`.
- The sheet lists every discovered tool with a toggle; toggling a tool persists the `enabledMCPToolIds` set via `SettingsManager`.
- Server detail includes bulk controls directly below the enable-all switch to update availability or permission for every
  configurable tool with one persisted state change.
- The `ChatViewModel+Agent.makeToolRegistry()` method reads the enabled set and only injects activated `MCPTool` instances.
- MCP descriptions are carried by formal tool definitions. The custom agent system prompt does not duplicate MCP tools, so
  disabling a tool removes its advertisement from subsequent rounds of an active response.
- A corresponding MCP section in Settings allows the same tool management and re-fetch from a Settings context.

### Authorization

- Every enabled MCP tool defaults to `ask`; built-in tools and web search remain automatic.
- Policies are `alwaysAllow`, `ask`, and `deny`. A denied enabled tool remains advertised and returns an ordered synthetic
  denial result, while a disabled or stale-configuration tool is omitted from definitions.
- Bulk permission changes update every configurable tool in the selected server and emit one settings notification.
- Policy identity includes the normalized endpoint, an opaque credential scope stored in Keychain, server/tool identity,
  description, and the complete canonical input schema. Changing any of them invalidates the prior policy.
- Calls requiring approval are presented as one batch before any tool in that round starts. Decisions remain per call;
  permanent choices apply to every repeated call of the same tool and are persisted only when the user continues.
- On iOS, the approval sheet uses the medium detent with internal scrolling. The accessible close action denies every
  pending request without competing with the centered title.
- Closing the review denies every pending call once. Stopping or leaving the chat cancels the pending authorization.
- Tool availability, configuration identity, enablement, and policy are revalidated immediately before execution. A server
  configuration change also cancels the active agent so conversation data cannot cross endpoints.
- Malformed or non-object input schemas and tools retained from a failed server are omitted from model definitions and
  cannot execute.
- MCP results are encoded as explicitly untrusted data before they are returned to the model; external result text is never
  treated as a source of tool instructions.
- Approval time is excluded from the agent timeout. Cancellation remains active while approval is pending.

### Relationship with Web Search

- MCP tools and web search are independent: a model with `.functionCalling` can use both simultaneously.
- Web search requires a configured search tool in Settings and the web search toggle to be on.
- MCP tools require the LiteLLM server to have at least one MCP server configured and individual tools to be enabled in the MCP Tools sheet.
- Both are integrated through the same `ToolRegistry` → `AgentStreamUseCase` pipeline.
- See `web-browsing.instructions.md` for the full flow table and implementation details
