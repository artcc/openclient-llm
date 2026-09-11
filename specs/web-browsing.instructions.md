---
description: "Use when implementing web browsing or web search capabilities, integrating web search via LiteLLM, displaying search results or citations in chat, or configuring search-related settings."
applyTo: "**/*.swift"
---

# Web Search — Integration via LiteLLM

## References

- LiteLLM Search API (`/v1/search`): https://docs.litellm.ai/docs/search/
- LiteLLM Function Calling: https://docs.litellm.ai/docs/completion/function_call

## Overview

Web search uses a **single mechanism**: an **agent loop** with a tool named `web_search`. The app never calls any search provider API directly — LiteLLM handles provider selection, API keys, and result fetching on the server side via its `/v1/search` endpoint.

- **No search API keys in the app** — keys live in LiteLLM's server environment
- **No direct calls to any search provider** (Brave, Perplexity, Tavily, etc.)
- **No manual context injection** — results are never fetched client-side and injected as system messages
- **No `web_search_options`** — the app never sends native web search parameters in the request body
- The LiteLLM base URL is the same one already configured by the user for chat

### Web Search Flow Table

| Condition | Globe Color | Behavior |
|-----------|------------|----------|
| Web search OFF | Grey | No search; function-calling models still use the agent loop with other built-in tools, while other models use regular streaming |
| Web search ON + `.functionCalling` + built-in search enabled | Accent | Agent loop with tool `web_search` → executed via `/v1/search` endpoint |
| Web search unavailable because the model lacks `.functionCalling`, no search tool is configured, or the built-in tool is disabled in Settings → Tools | Red | The toggle does not change state; no search occurs |

### How It Works (Agent Loop with `/v1/search`)

For models with function calling capability. The app registers a tool named `web_search` and runs an **agentic loop**:

1. App sends request with `tools: [web_search]` + `tool_choice: "auto"`
2. Model responds with `tool_calls: [{"function": {"name": "web_search", ...}}]`
3. App's `AgentStreamUseCase` → `WebSearchTool.execute()` → calls `POST /v1/search/{search_tool_name}` (e.g., `/v1/search/brave-search`)
4. Search results sent back to model as tool result
5. Model may call tools again; the registry remains attached until the model answers or a safety limit forces a final request without tools

This works with **any model from any provider** (Ollama, OpenAI, Anthropic, Groq, etc.) as long as the model returns structured `tool_calls` (not text-plain JSON). The `/v1/search` endpoint is completely model-agnostic.

**Model detection**: `model_info.supports_function_calling == true` → `.functionCalling` capability.

**Known limitation**: Some small/specialized models (e.g., `qwen2.5-coder`) may emit tool calls as plain text in `content` instead of structured `tool_calls` in the response. In this case the agent loop cannot intercept them and the raw JSON is displayed as the assistant message.

### Why Not Native `web_search_options`?

Native web search (`web_search_options` in the request body) was intentionally removed because:

- **OpenAI** only supports it for search-dedicated models (`gpt-5-search-api`, `gpt-4o-search-preview`); regular OpenAI models reject it with HTTP 400
- **Provider-specific routing** creates fragile code paths that are hard to test and maintain
- The **agent loop approach works universally** across all providers and models with function calling
- One single method = simpler codebase, fewer bugs, consistent behavior

### Tool Name: `web_search` (Not `litellm_web_search`)

The app uses `web_search` as the tool name (not `litellm_web_search`) to **avoid triggering LiteLLM's server-side web search interception**. The interception feature may cause unexpected behavior with some providers like Ollama.

---

## LiteLLM Server Configuration (reference for users)

### Search Tools (required for `/v1/search`)

```yaml
search_tools:
  - search_tool_name: brave-search
    litellm_params:
      search_provider: brave
      api_key: os.environ/BRAVE_API_KEY
```

### Supported Search Providers (agnostic to the app)

| Provider | `search_provider` value | Server env var |
|----------|------------------------|----------------|
| Brave Search | `brave` | `BRAVE_API_KEY` |
| Perplexity | `perplexity` | `PERPLEXITYAI_API_KEY` |
| Tavily | `tavily` | `TAVILY_API_KEY` |
| Exa AI | `exa_ai` | `EXA_API_KEY` |
| DuckDuckGo | `duckduckgo` | `DUCKDUCKGO_API_BASE` |
| SearXNG | `searxng` | `SEARXNG_API_BASE` |
| Google PSE | `google_pse` | `GOOGLE_PSE_API_KEY` + `GOOGLE_PSE_ENGINE_ID` |
| Firecrawl | `firecrawl` | `FIRECRAWL_API_KEY` |
| Linkup | `linkup` | `LINKUP_API_KEY` |
| Serper | `serper` | `SERPER_API_KEY` |
| SearchAPI.io | `searchapi` | `SEARCHAPI_API_KEY` |

---

## Implementation

### Decision Logic (`streamWithWebSearch`)

```swift
func streamWithWebSearch(_ context: SendMessageContext) async {
    let useAgentMode = context.modelCapabilities.contains(.functionCalling)
    if useAgentMode {
        // The registry contains enabled, eligible built-in tools.
        // web_search also requires context.webSearchEnabled to be true.
        await performAgentStreaming(...)
    } else {
        // No search (disabled or no capabilities) → regular streaming
        await performStreaming(...)
    }
}
```

### Key Types

- `WebSearchTool` — Implements `ChatToolProtocol`, defines `web_search` function. On execution, calls `WebSearchUseCase` which hits `/v1/search/{search_tool_name}`
- `ToolRegistry` — Registers `WebSearchTool` only when web search is enabled; agent mode itself is automatic for function-calling models
- `AgentStreamUseCase` — Manages the agentic loop (see `agent-tool-calling.instructions.md`)
- `WebSearchUseCase` — Calls `APIClient.searchRequest()` → `POST /v1/search/{search_tool_name}`

### Tool Result Messages

When the agent loop handles `web_search`, tool result messages include the `name` field per OpenAI spec:

```json
{
  "role": "tool",
  "tool_call_id": "call_abc123",
  "name": "web_search",
  "content": "{\"results\": [...]}"
}
```

The `name` field is stored in `ChatMessage.toolName` and serialized via `ChatCompletionMessage.name`.

---

## Settings

- **Web search enabled**: Stored in `SettingsManager` (`UserDefaults`) and defaults to `false` when no value exists.
- **Built-in search tool enabled**: Managed independently in Settings → Tools and defaults to `true`. Disabling it
  removes advertisement and blocks new executions without changing the saved globe preference or search configuration.
- **Search tool name**: Stored in `SettingsManager` (`UserDefaults`) and defaults to the empty string. It must match a `search_tool_name` in LiteLLM configuration; Settings can discover tools through `GET /v1/search/tools` and select the first returned tool when the saved value is unavailable.
- **Maximum results**: Stored in `SettingsManager` (`UserDefaults`) and defaults to 10. `WebSearchUseCase` sends this value to LiteLLM, while `WebSearchTool` formats at most the first five returned results for model context and retains the full result array for source display.
- **Tool rounds**: The agent permits up to 15 iterations, 20 tool calls in total, and 8 calls in one iteration. These are agent safeguards, not user-configurable search settings.
