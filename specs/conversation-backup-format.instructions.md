---
description: "Use when exporting, importing, restoring, validating, or versioning OpenClient conversation backups."
applyTo: "openclient-llm/Shared/Features/Chat/**/*.swift"
---

# Conversation Backup Format Specification

## Scope

This specification defines the interoperable OpenClient JSON backup contract and, separately, the behavior of the current
importer. A single-conversation export contains one entry in `conversations`; a complete backup uses the same format and
contains every conversation available at export time.

## Interoperable Version 1 Contract

```json
{
  "format": "com.artcc.openclient-llm.conversations",
  "version": 1,
  "exportedAt": "2026-07-13T08:00:00Z",
  "conversations": [
    {
      "conversation": { "...": "Persisted Conversation fields" },
      "attachments": [
        {
          "messageId": "UUID",
          "attachmentId": "UUID",
          "data": "base64"
        }
      ]
    }
  ]
}
```

| Field | Type | Required | Contract |
|---|---|---|---|
| `format` | String | Yes | Exactly `com.artcc.openclient-llm.conversations`. |
| `version` | Integer | Yes | Exactly `1`. |
| `exportedAt` | ISO 8601 date | Yes | Document creation time. |
| `conversations` | Array | Yes | Zero or more exported conversations. |
| `conversation` | Object | Yes | A Codable persisted `Conversation`, including its messages and optional compatible metadata. |
| `attachments` | Array | Yes | Portable binary payloads referenced by `conversation`. |
| `attachments[].messageId` | UUID | Yes | Message containing the attachment metadata. |
| `attachments[].attachmentId` | UUID | Yes | Attachment identifier on that message. |
| `attachments[].data` | Base64 string | Yes | Binary attachment content. |

Version 1 rules:

- Dates are ISO 8601. Required fields must decode; unknown JSON keys are ignored.
- Conversation and message UUIDs are unique across the document. Each payload references attachment metadata on its
  declared message, and a message cannot contain duplicate payload entries for the same attachment UUID.
- Attachment bytes live in `attachments`; metadata `fileRelativePath` is retained only for Codable compatibility and is
  never a portable restore location. An unreadable local file may be omitted without preventing conversation export.
- Optional fields remain optional for older Version 1 documents. This includes model parameters, pin state, tags,
  `tagColors`, branch references, compacted-context metadata, and `imageGenerationAttempted`; their model decoders define
  defaults. Tags without a color use orange.
- `contextWindowTokens`, when present, is greater than zero. A context summary and its inclusive cursor are an indivisible
  pair: the summary is non-empty and the cursor identifies a message in the same conversation.
- Tag names remain strings in `tags`; optional `tagColors` maps those names to stable semantic color identifiers.

## Current Importer Behavior

- The importer decodes the complete document with ISO 8601 dates, then validates `format`, `version`, identifiers,
  attachment references, and context metadata before persisting anything. Malformed UUIDs, dates, or required fields
  invalidate the document; unsupported format or version is rejected explicitly after decoding.
- Imported conversations, messages, and attachments receive new UUIDs. Existing conversations are never overwritten.
  Branch references are remapped when both endpoints are imported; external references are removed. Summary cursors use
  the message UUID map.
- Attachment payloads are decoded and written to new local paths; exported paths are ignored. Missing or invalid base64
  for declared attachment metadata skips that attachment and increments `skippedAttachmentCount`; a missing required
  `data` field or an invalid payload reference invalidates the document.
- Repeated attachment UUIDs with identical bytes within one conversation share a new UUID. Conflicting bytes receive
  separate UUIDs per message and ambiguous textual or tool references remain unchanged. UUID scope is per conversation.
- References to successfully restored images are remapped in context summaries, assistant content, and the recognized
  `analyze_images` and `list_image_attachments` tool fields. Matching is case-insensitive and limited to complete canonical
  UUID tokens; identifiers, filenames, paths, PDFs, missing payloads, user/system content, prompts, reasoning, and unrelated
  metadata are not rewritten.
- Recognized JSON tool envelopes are remapped without normalizing unrelated content. Malformed, deeply nested, or unknown
  JSON and wrappers remain unchanged rather than invalidating an otherwise valid backup. Tool identity comes from
  `toolName` or an unambiguous assistant call with the same `toolCallId`.
- Import never executes tool calls. Tool transcripts, including `imageGenerationAttempted`, are restored as historical
  data only.
- Persistence is atomic for the import batch: a failure removes newly written attachments and rolls back every conversation
  already restored by that document.

## Privacy And Limits

Backups contain full conversation content, tool transcripts, and raw attachment bytes. Store and share them only through
trusted encrypted locations. Version 1 defines no artificial file-size or conversation-count limit; device storage and
memory are the practical limits.

## Versioning

Any incompatible schema change requires a new integer `version`. Importers must reject unknown versions rather than infer
a schema. Compatibility or migration for another version must be explicit and covered by tests.
