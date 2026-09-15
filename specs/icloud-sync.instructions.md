---
description: "Use when implementing or changing iCloud synchronization, iCloud Documents storage, conflict resolution, cloud availability, or cloud data management."
---

# iCloud Documents Synchronization Contract

## Scope

OpenClient synchronizes conversations and their attachments, the user profile, memory items, custom prompt templates, and
their deletion metadata through the private iCloud Documents container. The contract is file based through `Codable` and
`FileManager`; SwiftData, CloudKit records, third-party databases, and server-side synchronization are outside its scope.

## Data-Safety Guarantees

- Existing local and cloud JSON files are user data and remain readable across compatible upgrades.
- Empty or missing data, unavailable containers, pending downloads, decode failures, and unsupported schemas never imply
  deletion.
- Writes and deletes begin only after all reconciliation inputs and deletion metadata that can affect the decision are
  current and validated.
- Reconciliation is deterministic and idempotent. At most one operation mutates local or cloud state at a time; triggers
  received during a run are coalesced into at most one follow-up run.
- Permanent deletion requires explicit user intent or durable deletion metadata created by that intent.
- A category failure is retained as a partial result and never converted into global success. iCloud file access does not
  block the main actor.

## Version 1 Container And Layout

Both app targets use the private ubiquity container `iCloud.com.artcc.openclient-llm` with the `CloudDocuments` service.
Neither the developer nor the configured LiteLLM server can access it.

```text
Documents/
  Conversations/<conversation UUID>.json
  Attachments/<conversation UUID>/<attachment file>
  ConversationTombstones/<conversation UUID>.json
  ConversationTombstones.json
  ConversationDeleteAll.json
  UserProfile.json
  UserProfileDeletion.json
  PromptTemplates/<template UUID>.json
  PromptTemplateTombstones/<template UUID>.json
  Memory.json
  MemoryTombstones.json
  CloudPurgeMarker.json
  SyncManifest.json
```

`ConversationTombstones.json` is the legacy aggregate tombstone file and is merged with per-record tombstones.
`ConversationDeleteAll.json` remains compatible conversation-wide deletion metadata. New user records are never stored in
metadata files. `CloudPurgeMarker.json` is the shared global deletion barrier, not a user record.

## Schema And Serialization

Version 1 is the current schema. A missing `SyncManifest.json` is valid legacy Version 1 and never means that the container
is empty or unsupported. When present, the additive manifest is:

```json
{
  "format": "com.artcc.openclient-llm.icloud-sync",
  "schemaVersion": 1,
  "minimumReaderVersion": 1
}
```

- `format` matches exactly. Versions are positive, `minimumReaderVersion <= schemaVersion`, and mutation is allowed only
  when `minimumReaderVersion` is supported. Unknown fields are ignored.
- A malformed manifest, unknown format, invalid version range, or unsupported minimum reader version makes cloud storage
  read-only for that run: no write, migration, or deletion is allowed.
- An incompatible layout requires a new schema version and explicit tested migration. Migration writes, reads back, and
  validates the new representation before recording completion; replaced or removed files are first preserved in local
  recovery storage, and old cleanup waits for verified synchronization.
- Synchronized JSON uses sorted, pretty-printed keys and ISO 8601 UTC dates with microsecond precision. Readers accept ISO
  8601 dates. Writes are atomic, coordinated where required, read back, byte-checked, and decoded before success.

## Runtime Contract

Persisted `isCloudSyncEnabled` records user intent only. Availability and `CloudSyncStatus` are ephemeral:

| `CloudSyncStatus` | Meaning |
|---|---|
| `disabled` | User intent is off; no synchronization work is active. |
| `checkingAvailability` | Account, container, schema, and initial metadata are being resolved. |
| `idle(lastSuccessfulSyncAt:)` | The container is usable, without asserting a complete current run. |
| `synchronizing` | Serialized reconciliation is running. |
| `waitingForDownloads` | Required ubiquitous items are not current; no writes are allowed. |
| `synchronized(lastSuccessfulSyncAt:)` | Every data category succeeded in the same run. |
| `unavailable` | The account or container is unavailable; user intent may remain enabled. |
| `failed` | A non-pending failure affects the recorded categories. |
| `incomplete` | Categories have mixed pending, unavailable, or failed outcomes; unaffected work is not reported as global success. |

The last successful date is local diagnostic state, not proof of present availability. Disabling sync cancels pending work,
observation, and retries without deleting data. Enabling performs availability, schema, and metadata preflight before any
user-data write.

## Reconciliation

Each category follows the same safety sequence: resolve the container and schema; gather metadata and request placeholder
downloads; stop without writes if required input is pending; decode local, cloud, and deletion inputs independently; merge
deterministically; persist and verify local then cloud output; and apply deletion only after its metadata is durable.

- Local-only records upload and cloud-only records download unless rejected by durable deletion metadata. An empty side
  contributes no records and never removes records from the other side.
- Conversations are keyed by `Conversation.id`; the newest valid `updatedAt` wins. A tombstone rejects versions not newer
  than its deletion date. Attachments are children of conversations; referenced files are materialized, and unreferenced
  cloud folders are removed only after verified parent reconciliation.
- Memory is merged by `MemoryItem.id`, and custom templates by `PromptTemplate.id`, using their modification values and
  durable per-item deletion metadata. Built-in templates are not cloud user data.
- The profile is a singleton resolved by modification metadata and `UserProfileDeletion.json`. Unsafe automatic choices
  remain conflicts.
- Equal modification values with different content are deterministic conflicts; the losing valid representation is
  preserved in local recovery storage before replacement.

## Tombstones And Purge

- Individual deletion stores durable metadata before removing payloads. Tombstones merge by newest deletion date and are
  retained so offline devices cannot resurrect stale records.
- Delete-all stores `CloudPurgeMarker.json` before deleting any category and journals per-category completion for safe,
  resumable cleanup. The marker rejects records whose modification value is not newer than `deletedAt`; later records can
  synchronize normally.
- Deletion is idempotent. An absent payload is success only when the required deletion metadata exists. Metadata is not an
  independently deletable user record.
- Partial purge failures preserve the marker and unfinished categories for retry; they never report complete deletion.

## Availability, Recovery, And Privacy

- Availability requires a current ubiquity identity and resolvable container URL. Identity changes and app activation
  invalidate the snapshot and require a new preflight.
- Metadata observation exists only while intent is enabled and the container is available. It establishes an initial
  baseline; events are debounced and coalesced, and idempotent comparison prevents write feedback loops.
- Errors distinguish unavailable account/container, pending downloads, unsupported schema, invalid data, coordinated file
  access failure, insufficient storage, and partial category failure. Transient retries use bounded backoff; disabling sync
  cancels them.
- A valid losing or replaced representation is preserved in local recovery storage. Corrupt or unrecognized files are
  preserved and reported. Recovery never uploads unvalidated data.
- Logs never contain raw paths, profile or memory content, conversation content, or attachment content.

## Certification

Changes to synchronization behavior require:

- Unit coverage against an injectable temporary cloud root.
- Deterministic two-device coverage with separate local roots and one shared cloud root.
- Cases for local-only, cloud-only, equal, divergent, pending, unavailable, corrupt, deleted, partial, and repeated inputs.
- iOS and macOS verification.
- Manual two-installation validation with a test iCloud account for placeholder and metadata behavior that the local harness
  cannot reproduce faithfully.
