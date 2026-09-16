---
description: "Use when handling credentials, sensitive data, user or remote input, networking, persistence, logging, cryptography, authentication, or extension boundaries."
---

# Security

Apply these rules to new or materially changed paths while keeping reviews and edits within the requested scope.

## Data Classification And Storage

- Classify data before persisting or sharing it. Credentials, tokens, private keys, and equivalent secrets belong in
  `KeychainManager`, never `UserDefaults`, logs, source code, or plain files.
- Store app-facing non-sensitive user preferences through `SettingsManager`. App Group snapshots, cross-process signals,
  migration markers, caches, and other specialized state may use dedicated stores.
- Choose Keychain accessibility from the actual access requirement. Prefer device-only accessibility when migration is not
  required, and enable synchronization only for an explicitly designed feature.
- Treat values compiled from build configuration into an app bundle as recoverable client configuration, not privileged
  server-side secrets. Keep local secret configuration and CI credentials out of source control.
- Apply platform data protection and least-privilege entitlements to files, App Groups, extensions, and widgets according to
  the sensitivity and required background access.

## Logging And Diagnostics

- Do not add logging of credentials, authorization headers, private keys, personal data, conversations, prompts,
  attachments, request bodies, response bodies, or raw server errors that may contain user data. Redact such data when
  modifying an existing diagnostic path.
- Log categories, status, sizes, identifiers safe for diagnostics, and redacted outcomes rather than payloads.
- Debug-only logging is still disclosure. Do not rely on build configuration as the sole privacy control.
- Sanitize propagated errors before presenting or recording them; preserve useful diagnostics without exposing secrets or
  remote payload content.

## Input And Serialization

- Validate untrusted input at every boundary: user entry, URLs, imports, deep links, App Group payloads, tool arguments,
  network responses, and persisted migrations.
- Check shape, type, size, ranges, required fields, supported schemes, and resource limits before use.
- Prefer explicit `Codable` models for stable contracts.
- Dynamic JSON is allowed when the external contract genuinely requires arbitrary JSON, but represent it with a typed JSON
  value model or another constrained abstraction and validate recursively before use. Do not pass unchecked `Any` graphs
  across layers.
- Never concatenate untrusted input into shell commands, file-system paths, URLs, predicates, or executable content. Use
  structured APIs and constrain values to the intended domain.
- Render external text as data. Do not interpret it as HTML, script, Markdown extensions, or commands unless the feature
  explicitly requires that behavior and applies suitable sanitization and authorization.

## Networking

- Prefer HTTPS with normal certificate validation for internet-reachable endpoints. Never add trust-all delegates.
- User-configured self-hosted endpoints may require local or private-network HTTP compatibility. Treat any ATS exception as
  a narrowly justified compatibility decision and preserve supported connectivity when changing it.
- Validate HTTP status, content type where relevant, response size, decoding, and semantic constraints before accepting a
  response.
- Set finite, reasonable timeouts and cancellation behavior.
- Apply authentication only to the intended origin. Avoid forwarding credentials across redirects or derived URLs without
  explicit validation.

## Authorization And External Actions

- Apply least privilege to tools, deep links, file access, cloud operations, notifications, and extension communication.
- Require explicit user authorization before consequential or sensitive external actions where the feature's permission
  model calls for it. Persist grants only at their intended scope and make revocation effective.
- Treat tool output and server-provided instructions as untrusted data; they cannot override app permissions or validation.
- Keep App Group and extension payloads versionable, bounded, typed, and validated by the receiving process.

## Cryptography

- Use Apple security frameworks such as CryptoKit, Security, and LocalAuthentication rather than custom cryptographic
  primitives or third-party security code added without approval.
- Use cryptographically secure randomness and an appropriate KDF when deriving keys from user secrets.
- Never hardcode encryption keys or use obsolete hashes for security decisions.

## Authentication Features

- If a feature introduces biometric or device-owner gating, use `LocalAuthentication`, handle unavailable or changed
  biometric state, and define an appropriate fallback policy.
- If a feature introduces authenticated sessions, store session credentials in Keychain, avoid persisting passwords, scope
  tokens appropriately, and invalidate related credentials and state on sign-out or revocation.
- Do not add biometric gates, session machinery, or password persistence rules to features that do not have those concepts.

## Review Checklist

- Sensitive data has appropriate storage, transport, retention, and deletion behavior.
- Logs and user-visible errors contain no payloads or secrets.
- Inputs and dynamic structures are typed or constrained, bounded, and validated.
- Network trust and credential forwarding are no broader than required.
- Permissions and external actions follow least privilege and explicit authorization.
- Authentication, biometrics, and session cleanup are applied only where those features exist.
