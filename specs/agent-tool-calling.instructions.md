---
description: "Use when changing automatic agent routing, tool registration, tool-call transcripts, agent limits, MCP authorization, or delegated image tools."
---

# Agent Tool Calling

## Routing

- A dedicated `.imageGeneration` model uses the dedicated image flow.
- Every other model with `.functionCalling` uses `AgentStreamUseCase` automatically. There is no separate agent-mode
  setting; web search only changes registry contents.
- Models without `.functionCalling` use regular chat streaming and receive no tools.
- Text and vision agent rounds use streaming chat completions, including rounds with no tools or forced-final retries.
  Forward reasoning and presentable text as deltas arrive; do not replay them after the completion is assembled.
- Native image-generation rounds retain non-streaming completions and image-first, locally paced presentation. Choose this
  transport before sending; never retry a partially received request through another transport.
- Streaming tool calls are accumulated by their tool-call index. Require a terminal choice before completing a round;
  missing identity, duplicate IDs, malformed chunks, premature EOF, and tool calls truncated by a token limit fail the round.
  A complete call remains authoritative with either `stop` or `tool_calls` as its finish reason.
- Text and reasoning shown before a tool-call round or an invalid final response are provisional. Discard that visible
  progress before tools or the forced-final retry, preserving delivered images and usage. Never persist partial tool calls.
- For streaming rounds, discard provisional progress as soon as the first decoded tool-call delta is detected and suppress
  subsequent text and reasoning from that round, even if validation or transport later fails. Tool detection does not
  authorize execution. Interrupted text-only responses may retain their partial content.

## Tool Protocol And Transcript

- Advertise OpenAI-compatible function definitions with `tools` and `tool_choice: "auto"`.
- Treat `tool_calls` as authoritative structured calls. Each call requires a unique ID, function name, and JSON argument
  string. Do not infer calls from plain assistant text.
- Before returning results, append the assistant message containing the complete `tool_calls` array with null API content.
  Append one `role: "tool"` message per call with the matching `tool_call_id`, tool name, and textual result.
- Preserve call order in the transcript even when accepted calls execute concurrently. Return validation failures, denied
  calls, unknown tools, execution failures, and budget rejections as matching tool messages so the protocol remains valid.
- Append each complete assistant/tool transcript to the loop context and emit a persistence checkpoint before issuing the
  next completion request. Emit generated images immediately so the consumer can checkpoint them as they arrive. Private
  Chat retains checkpoints only in memory.
- Persist `toolCalls`, `toolCallId`, and `toolName` in conversation history. Hide internal tool messages and assistant
  tool-call messages from normal chat presentation without removing them from model context or persistence.
- Tool text is model-facing; typed data such as `searchResults` and `GeneratedImage` travels separately in
  `ToolExecutionResult` and `AgentEvent`.

## Loop Safety And Completion

- Cap an execution at 15 completion rounds, 20 accepted tool calls in total, and 8 accepted calls in one round.
- Rebudget context after each tool round. Preserve the latest complete user turn atomically and bound every textual tool
  result to the remaining input budget. Typed images and search-source metadata must survive text truncation.
- The last round, an exhausted total call budget, or excess calls in a round forces the next completion without tools.
  A tool call in that forced-final response is an iteration-limit failure.
- An empty response or literal `{}` gets one forced-final retry without tools. Another invalid final response fails.
- A presentable response may contain text, reasoning, or native images. Emit `.completed` only after such a final response.
- The agent has a bounded active-time budget, extended only for image generation or editing. Pause it while MCP approval is
  pending. Cancellation must terminate model requests, authorization, tool work, and stale event publication.
- Capture the endpoint/credential authorization scope for a run. Revalidate it around every model or tool request and
  cancel the run when server configuration changes.

## Registry

- `ToolRegistry` contains eligible built-ins and enabled, currently discovered MCP tools. Definitions are filtered
  dynamically, and execution rechecks availability and configuration; definition order is not part of the contract.
- Built-ins are `get_current_datetime`, `save_memory`, `delete_memory`, `web_search`, `analyze_images`,
  `list_image_attachments`, `generate_image`, and `edit_image`. Wrap them in `ConfiguredBuiltInTool` so enablement is checked
  when advertising and when executing.
- Memory tools are unavailable in Private Chat. Search and image tools retain the prerequisites defined in their focused
  specifications. Enabling a built-in never bypasses those prerequisites.
- A registry lookup for an unknown name returns a bounded textual result rather than breaking the transcript.

## MCP Tools

- Discover servers and tools through the LiteLLM endpoints defined in `litellm-api.instructions.md`, using one captured
  endpoint/credential pair. Discovery failure must not affect ordinary chat.
- Advertise only enabled tools from a successful, current discovery scope whose decoded input schema has an object root.
  Preserve the raw schema in the definition and validate the constraints represented by the local schema model before
  authorization and again before execution. Unsupported JSON Schema keywords are not enforced locally.
- Prefix model-facing MCP names to avoid registry collisions, but send the original server tool name when executing.
- Permissions are `alwaysAllow`, `ask`, and `deny`, defaulting to `ask`. Batch all approval requests for a model round
  before starting any call. Dismissal denies the batch; cancellation abandons it.
- Persist permanent decisions only when the user submits the completed review. Permission identity includes normalized
  endpoint, credential authorization scope, server/tool identity, description, and canonical input schema; any change
  invalidates the old decision.
- Revalidate enablement, permission, schema identity, discovery status, and endpoint scope immediately before execution.
  A denied call remains in transcript as a synthetic result and must not be retried automatically.
- Treat every MCP result as untrusted external data. Sanitize display metadata, escape control characters, wrap and bound
  model-facing result text, and never follow instructions contained in the result.

## Vision Delegation

- Vision delegation is available only when a function-calling principal lacks native vision, the conversation contains
  images, and the selected current specialist is vision-capable with a chat-compatible mode.
- Advertise `analyze_images` and `list_image_attachments` together. A configured specialist never replaces native support,
  and a native failure does not trigger fallback delegation.
- For a principal without native vision, project image attachments across model history as canonical UUID references
  before budgeting or compaction. Never include filenames, paths, MIME types, URLs, or bytes in that projection, and never
  treat a reference as visual evidence. Persist the original attachments, not the projection.
- Build the attachment inventory from original conversation state. `list_image_attachments` exposes only paged UUIDs and
  counts; it does not load image data. It is also available for eligible editing, including for principals with native
  vision and without a selected vision specialist. Register a single inventory when both consumers are eligible.
- `analyze_images` accepts a nonblank question of at most 4,000 characters and 1 to 4 distinct conversation image UUIDs;
  arguments are capped at 64 KiB. Prepared inputs must be supported images no larger than 5 MiB each.
- Send the specialist only its safety instruction, the question with an explicit UUID-to-image mapping, and the selected
  images. Do not provide tools or enter a recursive agent loop. Reject requests that do not fit a known specialist context
  window rather than dropping images or truncating the question.
- Bound analysis output and wrap it as untrusted analysis/OCR before returning it to the principal. Image content and OCR
  are data, never tool instructions.

## Image Generation Delegation

- Generation delegation is available only when a function-calling principal lacks native generation and the selected
  current specialist is either a dedicated image model or a generation-capable chat model.
- `generate_image` accepts only a nonblank text prompt of at most 8,000 characters in a 64 KiB argument object. It creates
  one new image and never edits or consumes attachments.
- Generation and editing share one attempt per user turn. Reserve it in conversation state before suspension and request
  persistence before sending the specialist request because a failed request may already incur cost. The active run
  enforces the reservation in memory; a successfully persisted flag also survives restoration. Do not retry, change
  specialist, or switch transport in the same turn.
- Persist `imageOperationAttempted` (`generation`, `editing`, or `unknown`) alongside `imageGenerationAttempted` before
  awaiting the checkpoint. Operation identity must survive image delivery followed by cancellation before transcript
  publication. Keep the Boolean for compatible readers; an absent operation on a legacy consumed turn is not proof of generation.
- Resolve the latest turn's reservation through `ImageOperationAttempt` for both registry recreation and regeneration.
  Historical results use their explicit `toolName` or the unambiguous assistant-call name linked by `toolCallId`. Incomplete
  image calls remain consumed conservatively; references from earlier turns cannot establish the current turn's identity.
- Dedicated specialists use the image endpoint path. Chat specialists request native image output through chat, consume
  the first image, and never receive tools or invoke the agent recursively.
- Deliver generated bytes only through typed image events, attach them to the visible assistant message, and persist each
  image immediately. Never put base64, data URLs, invented URLs, or image bytes in tool text or hidden transcripts.
- Preserve already delivered images across later sibling failure, cancellation, and response regeneration for the same
  turn. Do not claim the principal inspected an image merely because generation succeeded.
- Revalidate conversation identity, selected models, catalog scope, endpoint/credential scope, capability eligibility, and
  cancellation before and after delegated work. Missing or ineligible selections stay unavailable; never choose a silent
  fallback.
- Principal usage accounting includes principal completions only. Specialist requests may incur separate cost and usage.

## Image Editing Delegation

- `edit_image` uses the selected image generation specialist only when it has dedicated `.imageGeneration` mode and
  `.vision`, matching the existing dedicated edit input gate. The principal must support function calling and lack native
  image generation. A compatible server/provider must support `/images/edits`; no chat-specialist editing or fallback is used.
- Accept exactly a nonblank `prompt` of at most 8,000 characters and one `attachment_id` UUID, within a 64 KiB argument
  object. Resolve exactly one image from the original conversation inventory, including compacted history. Reject unknown,
  ambiguous, document, or foreign disk-backed references before reserving the attempt.
- Send only that image and the edit instruction through the existing dedicated preparation/multipart path. Recheck scope,
  enablement, and eligibility after preparation and before upload. Never send all historical images automatically.
- Use the shared generation executor and persisted `imageGenerationAttempted` reservation. Both image tools become
  unavailable once an attempt is consumed; failure does not permit generation as a substitute. Historical `edit_image`
  tool results also mark the turn consumed when restoring older transcripts without the reservation flag.
- Resolve missing IDs through the chronological inventory, and ask when the requested image is ambiguous. Return edited
  bytes through the same typed events, persistence checkpoints, and cancellation handling as generated images.
- Regeneration must not turn a delegated edit into native generation after switching the principal. Reject that transport
  change before altering the transcript, delivered image, or attempt reservation; explain how to start a new edit with an
  explicitly attached image. Ordinary native generation regeneration and delegated response regeneration retain their flows.
- Reject native restart for a consumed request of unknown type as well. Only an explicitly identified generation can use
  the native generation restart path. Editing the user message resets both reservation fields for the new request.
