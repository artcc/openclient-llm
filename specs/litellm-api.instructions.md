---
description: "Use when changing OpenAI-compatible or LiteLLM networking, model discovery, chat/SSE transport, images, MCP endpoints, health checks, or network logging."
---

# LiteLLM API

## Configuration And Layering

- Build API URLs by appending each repository's endpoint path to the user-configured server base URL. The current endpoint
  set mixes OpenAI-compatible paths such as `models` with LiteLLM paths such as `v1/search/tools`; preserve those spellings
  and test base-path behavior when changing URL construction. Add `Authorization: Bearer <key>` only when the Keychain
  value is nonempty; never hardcode credentials.
- `APIClient` owns HTTP construction, decoding, SSE transport, multipart uploads, downloads, and typed `APIError` mapping.
  Repositories map endpoint DTOs, UseCases apply business rules, and ViewModels coordinate them.
- Use `.convertFromSnakeCase` for API response decoding. Keep request models `Encodable` and transport values `Sendable`.
- Use a captured endpoint/key pair for operations whose authorization scope must not change in flight, including MCP and
  delegated image work. Ordinary clients may read current settings per request.

## OpenAI-Compatible Endpoints

- `GET /models` is the required model catalog endpoint.
- `POST /chat/completions` serves ordinary streaming chat, streaming text/vision agent rounds, and non-streaming calls
  including native image-generation agent rounds.
- Streaming requests use SSE data events and terminate on `[DONE]`. Accept `data:` with or without one following space,
  join multiple data fields with newlines, and dispatch only at a blank-line event boundary. Support LF, CRLF, and CR line
  endings and an initial UTF-8 BOM; ignore comments and other fields. Discard an unfinished event at EOF. Decode content,
  reasoning, usage, and native image deltas without retaining raw chunks after processing.
- Agent requests send OpenAI-compatible `tools`, `tool_choice: "auto"`, assistant `tool_calls`, and `role: "tool"`
  messages as specified in `agent-tool-calling.instructions.md`.
- Agent streaming requests include usage reporting. Accumulate optional tool-call identity/name/argument deltas by index;
  the response DTO for a complete tool call must not be used to decode an individual delta. Read trailing usage chunks with
  empty choices. Require a terminal choice and successful transport completion before returning an assembled response.
- Fail malformed agent chunks instead of skipping them; dropped argument fragments must not change an executed tool call.
  Do not expose raw payloads in errors or automatically resend a failed streaming completion.
- Notify the agent when the selected choice first contains decoded tool-call deltas, before validating those calls. Stop
  publishing text and reasoning for that round, while still accumulating and validating its full response.
- Multimodal input uses `image_url` content parts with base64 data URLs after the attachment preparation and size checks.
  PDFs remain text extraction inputs.
- Historical assistant images must not become `image_url` parts in assistant content: the base Chat Completions contract
  accepts images as user input. At request serialization, keep assistant text and tool transcripts in their original roles
  and include those images, with their canonical attachment UUIDs and assistant-origin context, in the next user message.
  If no user follows, append one context-only user message after the completed transcript. Never interrupt a tool-call/result
  block or mutate persisted history. Use the same projection for regular, agent, streaming, and buffered completions.

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
- The agent's `edit_image` tool reuses that multipart edit flow with one explicitly resolved conversation image and the
  selected dedicated, vision-capable image specialist. Its authorization scope and eligibility are checked again after
  attachment preparation, immediately before upload. It never falls back to text-only generation or a chat transport.
- Dedicated generation requests include `response_format: "b64_json"` only for explicit `dall-e-2` and `dall-e-3` IDs;
  omit it for GPT image models and unknown or aliased IDs, which may return base64 data or an HTTP(S) URL.
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

- Validate HTTP status before decoding. Map authentication, rate limiting, transport, timeout, and malformed responses to
  the existing typed errors without exposing server payloads. Preserve current cancellation behavior unless the task
  explicitly changes it together with its callers.
- Preserve the limits already enforced for generated images, MCP values, tool results, and delegated image inputs. New or
  changed upload and download paths should reject oversized content as early as their transport API permits. Accept remote
  image downloads only on the dedicated image response path and only over HTTP(S).
- Log request method, relative endpoint, status, counts, sizes, timing-relevant state, and redacted errors only in debug
  builds. Never log request or response payloads, SSE chunk previews, prompts, messages, tool arguments/results, OCR,
  base64/data URLs, downloaded content, API keys, or authorization scopes.
