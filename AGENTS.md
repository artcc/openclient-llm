# AGENTS.md

Project-wide orchestration guide. Read this file before changing the repository, then read every specification relevant to the task. Focused specifications are living project contracts and must remain aligned with the implementation.

## Source Of Truth

Use this precedence according to the kind of information involved:

1. The user's explicit request and constraints for the current task.
2. Repository configuration and manifests for configured facts, including `openclient-llm.xcodeproj/project.pbxproj`,
   `.swiftlint.yml`, plists, entitlements, schemes, and CI workflows.
3. The focused specification for intended behavior, invariants, compatibility, and implementation constraints; a more
   specific spec takes precedence over this overview.
4. Compiled source code and tests as evidence of the current implementation and established local conventions.
5. This file for project-wide orchestration.
6. Descriptive documentation and examples, which must not override configuration, specifications, or implementation.

Repository instructions take precedence over generic agent guidance. A disagreement between a spec and the code is project
drift, not permission to ignore the spec. Determine whether the task changes the contract or restores the implementation;
then update both in the same change. If intent remains unclear, stop and ask for clarification.

## Operating Rules

- Work only inside this repository. The only exception is an artifact outside it that the user explicitly provides.
- Do not inspect installed SDKs, `DerivedData`, caches, system libraries, package caches, or other external paths to infer
  implementation details. Prefer official online documentation for external APIs, especially Apple frameworks.
- Read directly related files and all applicable specs before editing.
- Preserve the architecture, conventions, and nearby implementation patterns unless the task explicitly changes them.
- Keep applicable specs synchronized whenever behavior, compatibility, architecture, or a documented invariant changes.
  Do not leave a known mismatch for a later documentation pass.
- Do not discard, overwrite, or reformat unrelated user changes. Limit edits to the requested scope.
- Do not add or update dependencies without explicit permission. Read package declarations from the Xcode project rather
  than duplicating their inventory here.
- Ask before builds, tests, SwiftLint, formatters, type checks, or other validation commands. Use the smallest relevant
  validation once authorized.
- Use the project `xcode-verify` skill for Xcode validation; it owns setup and fallback details, while
  `.xcodebuildmcp/config.yaml` owns the default project, scheme, and simulator selection.
- Do not commit, push, amend, or perform destructive Git operations unless explicitly requested.
- Run `git diff --check` before reporting implementation work complete, unless the user forbids Git commands.

## Specifications

Specifications use the `.instructions.md` suffix and valid YAML front matter with a `description`; add `applyTo` when the
scope is expressible by path. Update this table when adding or removing a spec.

| File | Read when |
|---|---|
| `agent-tool-calling.instructions.md` | Implementing tool calling, tool UI, or the agent loop. |
| `architecture.instructions.md` | Creating Swift files, features, targets, or changing layer boundaries. |
| `changelog.instructions.md` | Updating `CHANGELOG.md`. |
| `chat-visual-style.instructions.md` | Designing chat-specific SwiftUI. |
| `code-style.instructions.md` | Writing or reviewing Swift style. |
| `concurrency.instructions.md` | Working with async code, isolation, tasks, or `Sendable`. |
| `conversation-backup-format.instructions.md` | Changing conversation backup export, import, validation, or versioning. |
| `design-ui.instructions.md` | Designing general SwiftUI, accessibility, haptics, or animation. |
| `icloud-sync.instructions.md` | Changing iCloud synchronization, storage, conflicts, or cloud data management. |
| `litellm-api.instructions.md` | Changing LiteLLM/OpenAI-compatible API integration. |
| `readme.instructions.md` | Updating `README.md`. |
| `security.instructions.md` | Handling sensitive data, input, credentials, networking, or security review. |
| `swiftui-multiplatform.instructions.md` | Building shared iOS, iPadOS, or macOS SwiftUI. |
| `testing.instructions.md` | Adding or changing tests, fixtures, or mocks. |
| `version.instructions.md` | Changing release versions, build metadata, or TestFlight notes. |
| `web-browsing.instructions.md` | Implementing web search or browsing features. |

## Architecture At A Glance

- The app uses SwiftUI and connects to a user-configurable LiteLLM/OpenAI-compatible server.
- Shared app code belongs in `openclient-llm/Shared/` and is compiled by the iOS/iPadOS and macOS app targets.
- Platform-only app code belongs in `openclient-llm/` or `openclient-llm-macOS/` as appropriate.
- `ShareExtension` is standalone and does not link the shared feature layer. `WidgetsShared/` is compiled by both widget
  extensions; widget targets likewise do not link the shared feature layer.
- Cross-target App Group models and stores must retain intentional target membership and compatible persisted formats.
- The usual flow is View -> ViewModel -> UseCase -> Repository -> APIClient/local storage, with Managers for transversal
  services. Do not add pass-through layers solely to satisfy the diagram.
- ViewModels use `@Observable`, remain explicitly `@MainActor`, own asynchronous state mutation, and generally receive UI
  events through `send(_:)`. Do not introduce `ObservableObject` or `@Published`.
- `SettingsManager` is the app-facing settings facade: its credential and authorization-scope APIs delegate to
  `KeychainManager`, while non-sensitive preferences use `UserDefaults`. Preserve that storage boundary.

## Change Completion

- Keep user-facing source strings in English and localize them. Do not edit `Localizable.xcstrings` manually.
- Follow `.swiftlint.yml` rather than copying its numeric thresholds into guidance.
- Verify target membership when creating or moving source files.
- Update structural documentation when intentionally changing targets, top-level ownership, or platform strategy.
- Report what changed, what was not validated, and any remaining risks.
