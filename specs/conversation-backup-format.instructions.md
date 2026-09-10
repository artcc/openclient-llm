---
description: "Use when exporting, importing, restoring, validating, or versioning OpenClient conversation backups."
applyTo: "openclient-llm/Shared/Features/Chat/**/*.swift"
---

# Conversation Backup Format Specification

## Scope

This specification defines the OpenClient JSON format used to export and restore conversations. It is the authoritative contract for both single-conversation exports and complete backups.

A single-conversation export contains one element in `conversations`. A complete backup contains every conversation available at export time. Both use the same document structure and version.

## Version 1 Schema

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

| Field | Type | Required | Definition |
|---|---|---|---|
| `format` | String | Yes | Must equal `com.artcc.openclient-llm.conversations`. |
| `version` | Integer | Yes | The document schema version. Version 1 is the current supported version. |
| `exportedAt` | ISO 8601 date | Yes | Time when the export document was created. |
| `conversations` | Array | Yes | Zero or more exported conversations. |
| `conversation` | Object | Yes | Persisted OpenClient conversation, including messages, parameters, tags, optional tag colors, pin state, timestamps, tool data, web search results, branch references, manual context settings, and optional compacted-context metadata. |
| `attachments` | Array | Yes | Portable attachment payloads associated with messages in `conversation`. |
| `attachments[].messageId` | UUID | Yes | Identifier of the message containing the attachment. |
| `attachments[].attachmentId` | UUID | Yes | Identifier of the attachment in that message. |
| `attachments[].data` | Base64 string | Yes | Binary attachment content. |

## Export Rules

- Every export writes the format identifier, current version, and export timestamp.
- Attachment payloads are separate from conversation metadata so their binary content is portable.
- An attachment whose local file cannot be read is omitted from `attachments`; the conversation remains exportable.
- `fileRelativePath` is preserved in conversation metadata for Codable compatibility but is not a portable location and must not be used when restoring.
- Context summaries and their inclusive compacted-message cursor are preserved when present; they are optional so Version 1 imports created before context compaction remain valid.
- Tag names remain encoded in `tags` as strings. The optional `tagColors` object maps those names to stable semantic color identifiers so Version 1 backups remain readable by older app versions.
- `contextWindowTokens` must be absent or greater than zero.
- A context summary and cursor form an indivisible pair; the summary must contain text and the cursor must reference a message in the same conversation.

## Import Rules

- An importer must reject documents whose `format` or `version` is unsupported.
- The current importer first decodes the complete `ConversationExportDocument` with ISO 8601 dates, then checks `format` and `version`. A malformed schema therefore reports an invalid document even if its raw format or version value would also be unsupported.
- `ConversationExportDocument`, `ExportedConversation`, and `ExportedAttachment` use synthesized `Codable`: all fields shown as required must decode successfully, unknown JSON keys are ignored, and malformed UUIDs or dates reject the whole document.
- `Conversation` has a compatibility decoder: context metadata, model parameters, pin state, tags, tag colors, and branch references may be absent and receive their implemented nil/default values. Tags without a color use orange. Message and attachment compatibility is governed by their own custom decoders.
- Conversation IDs and message IDs must be unique across the document.
- Every attachment payload must reference an attachment on the specified message. Duplicate attachment payloads are invalid.
- Imported conversations, messages, and attachments receive new UUIDs. Existing local conversations are never overwritten.
- Messages may contain an optional `imageGenerationAttempted` boolean reservation. Preserve it on import and branching;
  older Version 1 documents without the key remain valid and decode it as absent. This local metadata is not a model-API
  field and prevents repeating a generation whose attempt was saved before its tool transcript arrived.
- Before restoring messages, attachment UUIDs are allocated per conversation for metadata with a present, decodable
  base64 payload. Repeated original attachment IDs with identical bytes share one new ID within that conversation,
  including across messages; Version 1 does not reject duplicate attachment metadata. This preserves preexisting
  ambiguous identity rather than arbitrarily selecting one attachment. If the same original ID has conflicting payload
  bytes, allocate separate new IDs per message and leave all textual/tool references to that ID unchanged: sharing a
  persisted path would otherwise introduce a new import failure or data loss. The same old ID in different conversations
  receives independent new IDs.
- References to restored image UUIDs are remapped in `contextSummary` and assistant `content`, including later model
  responses without tool metadata. Text replacement is case-insensitive and limited to complete canonical UUID tokens;
  UUIDs embedded in identifiers, filenames, or slash/backslash paths are not replaced. Summary cursors continue to use
  the separate message-ID map. PDF IDs and IDs without any restored image payload are not rewritten in text.
- For assistant `analyze_images` calls, structurally remap only `attachment_ids` array entries and explicit UUID tokens in
  `question`. For tool results, structurally remap `list_image_attachments.image_attachment_ids`, and UUID tokens in the
  `analyze_images` wrapper's `untrustedExternalToolResult` string or legacy plain-text analysis. Follow recognized nested
  wrappers up to eight levels, covering the tool's wrapper plus the agent's result wrapper. Deeper, malformed, or
  unrecognized wrappers stay unchanged.
- JSON remapping replaces only selected string tokens; preserve other bytes, including whitespace, key order, array
  order, unknown fields, and numeric precision/range. Do not decode unknown numbers into fixed-precision numeric types.
  The local scanner leaves JSON deeper than 128 levels unchanged rather than rejecting the backup. Replacement strings
  may use equivalent JSON escaping; unrelated tokens retain their original spelling.
- Tool results are identified by their explicit `toolName`, or, when absent, by an unambiguous assistant call name for
  their `toolCallId` in the same conversation. Other tools (including image generation and external tools), user/system
  message content, system prompts, reasoning, filenames, and unrelated metadata remain unchanged. No tool is executed
  during import. Malformed JSON arguments/results and unrecognized JSON wrappers remain unchanged, without rejecting
  an otherwise valid backup. Missing image payloads can therefore leave historical references unresolved; never invent
  replacement references for omitted attachments. Version 1 has no finer provenance for UUID mentions in assistant text
  or summaries, so exact tokens matching restored images are treated as references there, even when quoted by the model.
- Imported attachment data is written to a new local path. Exported `fileRelativePath` values are ignored.
- After the document has decoded and validated, a missing payload for attachment metadata or an invalid base64 payload omits only that attachment and increments `skippedAttachmentCount`. A missing required `data` field in an exported attachment object fails document decoding instead.
- Branch references are remapped when the referenced conversation or message is present in the document; external references are removed.
- Invalid context windows, summaries, or summary cursors reject the document before any conversation is restored.
- If a conversation cannot be persisted, its newly written attachments are removed. If a later conversation fails, earlier conversations restored from the same document are rolled back.

## Privacy And Limits

Backup files include full conversation content and raw attachment data. They must only be stored or shared through trusted, encrypted locations.

Version 1 imposes no artificial file or conversation-count limit. Available device storage and memory remain the practical limits.

## Versioning

Incompatible changes require a new integer `version`. Importers must reject unknown versions rather than infer a schema. Any migration support must be explicitly implemented and covered by tests.
