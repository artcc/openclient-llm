---
description: "Use when changing OpenAI-compatible or LiteLLM networking, model discovery, chat/SSE transport, images, MCP endpoints, health checks, or network logging."
---

# LiteLLM API

## Configuration And Layering

- Build every API URL relative to the user-configured base URL. Add `Authorization: Bearer <key>` only when the Keychain
  value is nonempty; never hardcode hosts or credentials.
- `APIClient` owns HTTP construction, decoding, SSE transport, multipart uploads, downloads, and typed `APIError` mapping.
  Repositories map endpoint DTOs, UseCases apply business rules, and ViewModels coordinate them.
- Use `.convertFromSnakeCase` for API response decoding. Keep request models `Encodable` and transport values `Sendable`.
- Use a captured endpoint/key pair for operations whose authorization scope must not change in flight, including MCP and
  delegated image work. Ordinary clients may read current settings per request.

## OpenAI-Compatible Endpoints

- `GET /models` is the required model catalog endpoint.
- `POST /chat/completions` serves ordinary streaming chat, non-streaming calls, and non-streaming agent rounds.
- Streaming requests use SSE lines prefixed with `data: ` and terminate on `[DONE]`. Decode content, reasoning, usage, and
  native image deltas without retaining raw chunks.
- Agent requests send OpenAI-compatible `tools`, `tool_choice: "auto"`, assistant `tool_calls`, and `role: "tool"`
  messages as specified in `agent-tool-calling.instructions.md`.
- Multimodal input uses `image_url` content parts with base64 data URLs after the attachment preparation and size checks.
  PDFs remain text extraction inputs.

## LiteLLM Enrichment And Fallback

- `GET /model/info` is optional LiteLLM enrichment for capabilities, provider, mode, context/output limits, pricing, and
  supported output modalities. Match enrichment to `/models` by model ID.
- If `/model/info` is missing, fails, or is empty, keep `/models` usable. Treat capabilities, limits, pricing, and usage as
  optional; conversations may use a manually configured context window.
- When enrichment is unavailable, attempt Ollama `/api/show` capability enrichment from the server root without making
  that endpoint a prerequisite for chat.
- `supported_output_modalities` containing `image` adds `.imageGeneration` without changing model mode. Vision does not
  imply image generation, and absent metadata does not imply either capability.
- `ollama_chat/<model>` uses Ollama's structured chat tool-call transport and may retain `.functionCalling`.
  `ollama/<model>` uses legacy generate/JSON emulation; remove `.functionCalling` and
  `.parallelFunctionCalling` from that route even when metadata advertises them.

## Native And Dedicated Images

- A chat or completion model with `.imageGeneration` remains on `POST /chat/completions` and requests image/text output
  modalities. Do not redirect it to an image endpoint based only on capability metadata.
- Read native generated images from message images in non-streaming completions and delta images in SSE. Accept only
  bounded `data:image/...;base64,...` values, validate the decoded image, and derive its actual MIME type. Do not download
  remote URLs returned in chat image fields.
- Dedicated `.imageGeneration` models use `POST /images/generations`; the existing dedicated edit flow uses multipart
  `POST /images/edits`. Dedicated responses may contain bounded base64 data or an HTTP(S) URL handled by the existing image
  repository.
- Chat image generation accepts text only, returns the first native image, supplies no tools, and has no fallback to a
  dedicated endpoint. Dedicated generation and editing must not be described as the same capability.
- Generated output is capped at 25 MiB. Preserve typed image data out of model-facing tool text and persist it according to
  `agent-tool-calling.instructions.md`.

## LiteLLM-Specific Endpoints

- `POST /v1/search/{search_tool_name}` executes web search and `GET /v1/search/tools` discovers configured search tools.
  Search behavior belongs to `web-browsing.instructions.md`.
- `GET /v1/mcp/server` discovers MCP servers, `GET /mcp-rest/tools/list?server_id=...` discovers their tools, and
  `POST /mcp-rest/tools/call` executes a tool with server ID, original tool name, and parsed object arguments.
- Missing search or MCP endpoints disable only those optional features. They must not prevent model listing or chat.
- Connection testing uses `GET /models`. LiteLLM detection separately uses `GET /health/readiness` and requires a successful
  JSON response containing `litellm_version`.
- Audio transcription uses `POST /v1/audio/transcriptions`; speech synthesis uses `POST /v1/audio/speech`.

## Security And Logging

- Validate HTTP status before decoding. Map authentication, rate limiting, transport, timeout, malformed response, and
  cancellation failures to typed errors without exposing server payloads.
- Bound uploads, generated images, downloads, MCP arguments/results, and delegated image inputs before expensive decoding
  or allocation. Accept remote image downloads only on the dedicated image response path and only over HTTP(S).
- Log request method, relative endpoint, status, counts, sizes, timing-relevant state, and redacted errors only in debug
  builds. Never log request or response payloads, SSE chunk previews, prompts, messages, tool arguments/results, OCR,
  base64/data URLs, downloaded content, API keys, or authorization scopes.
- `ChatRepository` still includes a short payload preview when an SSE chunk cannot be decoded. Treat it as unresolved
  hardening, not as an approved logging pattern; remove or redact it when changing that error path.
