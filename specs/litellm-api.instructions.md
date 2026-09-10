---
description: "Use when implementing API client, networking layer, LiteLLM integration, chat completions, model listing, streaming SSE responses, or server health checks."
---

# LiteLLM API Integration

## Server Overview

LiteLLM is a self-hosted proxy that exposes an **OpenAI-compatible API** for multiple LLM providers (Ollama, OpenAI, Anthropic, Groq, etc.). The app connects to a single user-configured base URL.

## Configuration

- **Base URL**: User-configurable (e.g., `https://litellm.example.com`), stored in app settings
- **API Key**: Optional, via `Authorization: Bearer <key>` header
- **No hardcoded endpoints**: Always build URLs relative to the base URL

## Key Endpoints

### Chat Completions — `POST /chat/completions`

```json
{
  "model": "gpt-4",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "Hello"}
  ],
  "stream": true
}
```

- Supports streaming via **Server-Sent Events (SSE)** when `stream: true`
- Response follows OpenAI chat completions format
- For streaming: use `URLSession` bytes async sequence, parse `data: ` prefixed JSON lines
- Handle `[DONE]` sentinel to detect stream end

### Native Chat Images

- Input images use multimodal content parts with `type: "image_url"` and `image_url.url` containing a base64 data URL.
  `ChatRepository` uses the attachment's MIME type and the existing 5 MB prepared-input limit. This differs from the
  larger generated-output limit below. PDF attachments continue through existing text extraction, not visual delegation.
- Native generated output is read from `choices[0].message.images` for non-streaming agent completions or
  `choices[0].delta.images` for SSE. Both use `ChatCompletionResponse.ImageItem`, with `image_url.url` and optional
  `type` and `index` metadata. The supported URL form is `data:image/<subtype>;base64,...`.
- `GeneratedImageDecoder` bounds the encoded payload and predicted decoded allocation before base64 decoding, rejects
  empty/invalid images and decoded data over 25 MiB, and determines the actual MIME type from ImageIO/UTType rather than
  trusting the data URL's declared subtype. Do not hardcode PNG for typed chat-generated output.
- Remote HTTP(S) URLs are not supported for generated images returned through chat completions. Reject them rather than
  downloading them or falling back to an images endpoint. Dedicated image endpoints retain their existing URL handling.
- `GenerateChatImageUseCase` conforms to `GenerateImageUseCaseProtocol` and calls `ChatRepository.streamMessage` with one
  user text prompt and default parameters. It rejects empty prompts and all attachments, ignores text/reasoning/usage
  chunks, and returns the first image decoded as `GeneratedImage`; a stream without an image fails. It never supplies
  tools, invokes the agent recursively, or retries through a different transport.
- Chat image specialists and principals with native generation use `modalities: ["image", "text"]` through their captured
  chat repository. Ordinary chat and analysis requests retain `modalities: nil`; capability metadata never redirects a
  chat model to `/images/generations`. Non-streaming native image-only agent responses are valid final responses and emit
  `.generatedImage(GeneratedImage)` before paced text, alongside support for legacy `.image(Data)` events.

### List Models — `GET /models`

Returns available models in OpenAI format:

```json
{
  "data": [
    {"id": "gpt-4", "object": "model", "owned_by": "openai"},
    {"id": "ollama/llama3", "object": "model", "owned_by": "ollama"}
  ]
}
```

### Model Info — `GET /model/info` (optional LiteLLM enrichment)

Returns detailed information about each model, including capabilities and cost data pulled from model config and the [LiteLLM model cost map](https://github.com/BerriAI/litellm/blob/main/model_prices_and_context_window.json).

```json
{
  "data": [
    {
      "model_name": "gpt-4",
      "litellm_params": { "model": "gpt-4" },
      "model_info": {
        "id": "...",
        "key": "gpt-4",
        "max_tokens": 4096,
        "max_input_tokens": 8192,
        "max_output_tokens": 4096,
        "input_cost_per_token": 3e-05,
        "output_cost_per_token": 6e-05,
        "litellm_provider": "openai",
        "mode": "chat",
        "supports_vision": true,
        "supports_function_calling": true,
        "supports_parallel_function_calling": true,
        "supports_response_schema": false
      }
    }
  ]
}
```

Key capability fields in `model_info`:
- `supports_vision` — model can process images
- `supports_function_calling` — model supports tool/function calls
- `supports_parallel_function_calling` — model can call multiple tools in parallel
- `supports_response_schema` — model supports structured JSON output schema
- `supported_output_modalities` - optional output types; `image` adds generation capability while preserving `mode`.
  Absence, null, or a list without `image` does not imply generation. `supports_vision` alone never implies image output.
- `mode` — model type: `chat`, `completion`, `embedding`, etc.
- `litellm_provider` — provider name (openai, anthropic, ollama, etc.)
- `max_input_tokens` / `max_output_tokens` — context window limits

For Ollama models, `litellm_params.model` determines the tool-calling transport. `ollama_chat/<model>` uses Ollama's
native `/api/chat` structured `tool_calls` protocol. The legacy `ollama/<model>` adapter uses `/api/generate`, forces JSON
output, and emulates function calls through the prompt. The app therefore does not expose `.functionCalling` for
`ollama/<model>` routes even if model metadata advertises it; configure `ollama_chat/<model>` to enable agent routing.

`/model/info` is LiteLLM-specific enrichment, not a prerequisite for the OpenAI-compatible
chat API. Servers such as Ollama, vLLM, llama.cpp, or custom proxies may omit it or return an
error. In that case, continue with `/models` and `/chat/completions`; model capabilities, token
limits, pricing, and usage metadata must remain optional. Users can configure a manual context
window per conversation when the server does not provide `max_input_tokens`.

### Image And Vision Defaults

- Models exposes independent optional `Vision` and `Image Generation` selections in **Image and Vision**, persisted by
  `SettingsManager` as `selectedVisionModelId` and `selectedImageGenerationModelId`. They do not change the principal
  model, each offers `None`, and the same dual-capability chat model may fill both roles.
- Vision eligibility requires `.vision` with mode `.chat`, `.completion`, or `.unknown`. Image-generation eligibility
  requires dedicated `.imageGeneration` mode or `.imageGeneration` capability with one of those chat-compatible modes.
  Use `LLMModel.isVisionSpecialist` and `isImageGenerationSpecialist`, not capability labels alone, for eligibility.
- Keep missing/ineligible defaults as unavailable until the user selects a replacement or `None`. Never silently select
  another model, infer support when metadata is absent, or fall back between dedicated and chat transports.
- Native capability takes priority per role: `.vision` is native vision; dedicated image mode or `.imageGeneration`
  capability is native generation. `analyze_images` requires a function-calling principal without native vision, a
  selected eligible vision specialist in the current catalog, and image attachments. `generate_image` requires a
  function-calling principal without native generation and a selected eligible dedicated or chat image specialist.
- A principal without function calling cannot delegate. A principal with native support does not advertise the equivalent
  specialist tool, even after a native failure. Disabling a specialist does not disable native capabilities.
- See `agent-tool-calling.instructions.md` for UUID projection across history before budgeting/compaction, historical
  attachment IDs in definitions, argument limits, one generation attempt per turn, and image persistence checkpoints.

### Images - `POST /images/generations` And `POST /images/edits`

- Dedicated image models keep the existing `GenerateImageUseCase` / `ImageGenerationRepository` path.
  `/images/generations` sends JSON with `model`, `prompt`, `n: 1`, and `response_format: "b64_json"`.
- The existing dedicated editing flow uses multipart `/images/edits` with prepared `image` files, `model`, `prompt`, and
  `n: "1"`. This is not exposed by `generate_image`, which always sends an empty attachment list and is text-only;
  `GenerateChatImageUseCase` does not support editing either. Do not describe the existing dedicated editor as unsupported.
- Both dedicated requests use a 600-second network timeout. The repository consumes the first response image, supporting
  existing `b64_json` or downloaded URL output and `revised_prompt`. Its current base64 path labels output `image/png`;
  actual decoded MIME detection described above applies to the chat image decoder, not this legacy dedicated path.

### Search — `POST /v1/search/{search_tool_name}` and `GET /v1/search/tools`

`POST /v1/search/{search_tool_name}` executes the configured LiteLLM search tool. `GET /v1/search/tools` discovers search tools available on the server.

### MCP Tools — `GET /v1/mcp/server`, `GET /mcp-rest/tools/list`, `POST /mcp-rest/tools/call`

`GET /v1/mcp/server` returns the list of MCP servers configured on the LiteLLM instance:

```json
{
  "data": [
    { "server_name": "github_mcp", "server_id": "github_mcp" }
  ]
}
```

`GET /mcp-rest/tools/list?server_id={id}` lists the tools exposed by a given MCP server,
each with a `name`, optional `description`, and an `inputSchema` (recursive JSON Schema).

`POST /mcp-rest/tools/call` executes a tool with the given server ID, tool name, and
JSON `arguments` payload, returning `content` items with text and an optional `isError` flag.

These endpoints are LiteLLM-specific. If the server does not expose them, the app continues
without MCP tools and the MCP antenna icon in the chat input bar shows in grey.

### Audio — `POST /v1/audio/transcriptions` and `POST /v1/audio/speech`

Transcription uses multipart form data. Speech synthesis returns raw audio data.

### Connection And LiteLLM Detection

- Connection tests call `GET /models` with an optional bearer token.
- LiteLLM detection separately calls `GET /health/readiness` and treats a `200` JSON response containing `litellm_version` as LiteLLM.
- There is no current `GET /health` `APIClient` operation.

## Networking Architecture

- `APIClient` is a `Sendable` struct conforming to `APIClientProtocol`; it stores a `URLSession` and main-actor endpoint/key
  providers. Initialization can read settings dynamically or capture an explicit endpoint/credential pair.
- Request/response models as `Codable` structs in `Core/Networking/`
- Generic JSON and multipart responses use `JSONDecoder` with `.convertFromSnakeCase`; streaming decoding is performed by `ChatRepository`.
- Handle HTTP errors with typed `APIError` enum
- Default JSON/raw and ordinary chat streaming requests use 60 seconds; downloads use 120 seconds and the single-file
  multipart convenience overload uses 125 seconds. Dedicated image requests explicitly use 600 seconds. Onboarding
  connection and readiness checks use 30 and 10 seconds respectively; these are not user-configurable settings.
- Specialist and native chat image generation use `streamTimeoutInterval: 600` and a repository configured with a
  600-second non-streaming completion timeout. Ordinary chat and vision analysis retain their 60-second default.
  This is separate from the agent's active-time budget: 300 seconds base plus `AgentToolContext.additionalExecutionTime`,
  with 600 additional seconds when `generate_image` is initially advertised or the principal supports native generation.
  Increasing the loop budget alone does not extend a network request timeout.
- SSE streaming via `URLSession.bytes(for:)` async sequence
- Endpoints are passed as relative strings such as `models`, `model/info`, and `chat/completions`; `URL.appendingPathComponent` resolves them against the user-configured base URL.

### Specialist Request Boundaries

- Build specialist repositories with API clients capturing one endpoint/credential pair. Capture the model-catalog
  authorization scope and revalidate it, selected IDs, catalog eligibility, and principal capabilities when advertising
  tools and before/after asynchronous specialist work. Do not route in-flight conversation data to newly edited settings.
- Analysis sends only its question and 1 to 4 prepared images, with a specialist system instruction and no tools. Its
  question is limited to 4000 characters; generation accepts only a text prompt up to 8000 characters and one attempted
  request per user turn. Analysis/OCR is bounded untrusted data, never instructions for subsequent tools.
- Generated bytes travel through `ToolExecutionResult.images` and `.generatedImage(GeneratedImage)`, not tool text or
  hidden model-facing transcripts. Preserve images when truncating textual results. The visible assistant receives image
  attachments immediately, with normal persistence checkpoints; Private Chat keeps these attachments only in memory.
- Do not attribute specialist tokens or charges to the principal model. Agent usage aggregates principal completions
  only, while specialist calls may incur additional provider charges that are not included in those counters.

## Architecture Integration

- **Repository** wraps `APIClient` calls (e.g., `ChatRepository`, `ModelsRepository`)
- **UseCase** encapsulates business logic using repositories (e.g., `SendMessageUseCase`, `FetchModelsUseCase`)
- **ViewModel** calls UseCases via Event/State pattern — never calls `APIClient` directly
- **Manager** handles transversal concerns (e.g., `AuthManager` for API key, `ConnectivityManager`)

## Error Handling

- Network errors: no connectivity, timeout, DNS failure
- HTTP errors: 401 (auth), 429 (rate limit), 500 (server error)
- Parse errors: malformed JSON responses
- Server unreachable: LiteLLM not running or wrong URL
- Model-info unavailable: continue with minimal models and optional manual context settings
- Present user-friendly error messages, log technical details

## Current Debug Logging

`LogManager` prints only in `DEBUG` builds. `APIClient` logs request metadata, status codes, and byte counts rather than
successful response bodies or HTTP error payloads. `ChatRepository` still logs a short payload preview when skipping an
undecodable SSE chunk; this is a remaining payload-logging risk, not a pattern to extend. Image data URLs, base64, analysis
text, prompts, and credentials must not be added to logs. Prefer endpoints, sizes, and redacted diagnostics, and keep
production logging disabled.
