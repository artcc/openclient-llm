---
description: "Use when changing LiteLLM web-search configuration, registration, execution, source persistence, or citation context."
---

# Web Search

## Transport Contract

- `web_search` is the only web-search mechanism. The app must call the configured LiteLLM
  `POST /v1/search/{search_tool_name}` endpoint and must never call a search provider directly.
- Provider credentials and provider selection remain on the LiteLLM server. Do not add provider SDKs, provider-specific
  routing, client-side search keys, native `web_search_options`, or manual search-result injection.
- Discover available server configurations through `GET /v1/search/tools`. Settings supply the selected server tool name
  used in the endpoint; the model cannot choose or override it.

## Availability And Routing

- Web search requires a selected model with `.functionCalling`, a configured search tool name, the per-chat search setting,
  and the `web_search` built-in setting all to be enabled.
- Enabling search adds `WebSearchTool` to the normal registry; it does not enable agent mode. Function-calling models use
  the agent loop with or without search, while other models use regular streaming and cannot search.
- Recheck built-in enablement before execution. Disabling the built-in removes advertisement and blocks a pending new
  execution without erasing the saved chat preference or search configuration.
- Use the technical name `web_search`. Do not rename it to a LiteLLM-reserved or provider-specific function name.

## Execution And Results

- `WebSearchTool` accepts a JSON object containing a nonempty string `query`. Invalid or missing input returns a textual
  tool result that asks the model to answer without searching.
- `WebSearchUseCase` sends the configured result limit to LiteLLM and returns `[LiteLLMSearchResult]`.
- `WebSearchTool` returns `ToolExecutionResult.text` as concise, human-readable source entries followed by citation
  guidance. It returns the complete source array separately in `ToolExecutionResult.searchResults` for chat presentation
  and persistence. The tool message `content` is that formatted text, not JSON containing the results.
- Bound the model-facing formatted subset independently from the retained source array. The agent's remaining-context
  budget may further truncate text without removing `searchResults`.
- Tool transcript messages use the standard `role: "tool"`, matching `tool_call_id`, `name: "web_search"`, and formatted
  text content. Follow `agent-tool-calling.instructions.md` for ordering, persistence, cancellation, and finalization.

```json
{
  "role": "tool",
  "tool_call_id": "call_abc123",
  "name": "web_search",
  "content": "1. Source title\n   URL: https://example.com\n   Result snippet\n\nUse these sources..."
}
```

- Merge `searchResults` into the visible assistant message associated with the run so source UI is independent from the
  hidden tool transcript.
- Search failures propagate through normal tool execution handling as bounded textual errors; they do not introduce a
  second search path or silently fall back to a provider API.
