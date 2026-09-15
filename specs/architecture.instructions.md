---
description: "Use when creating Swift files or features, assigning target ownership, or changing View, ViewModel, UseCase, Repository, Manager, networking, or storage boundaries."
applyTo: "**/*.swift"
---

# Architecture

## Target Ownership

- Put code shared by the iOS/iPadOS and macOS apps in `openclient-llm/Shared/`.
- Put genuinely platform-specific app code in the corresponding app target directory. Use conditional compilation only
  for small platform differences inside otherwise shared code.
- Keep `ShareExtension` independent from the shared feature layer. Maintain compatible transfer types at its App Group
  boundary rather than coupling the extension to app-only code.
- Put widget code shared across platforms in `WidgetsShared/`. Widget extensions must not depend on the shared app feature
  layer.
- Treat files intentionally compiled into several apps or extensions as cross-target contracts. Verify target membership,
  platform availability, persistence compatibility, and extension-safe APIs when changing them.
- Read target membership, deployment settings, build settings, and package dependencies from the Xcode project. Do not
  infer them from folder names or duplicate inventories in guidance.

## Layering

The usual dependency direction is:

```text
View -> ViewModel -> UseCase -> Repository -> APIClient / local storage
                 \-----------------------> Manager
```

- Views render state and emit events. They do not perform persistence, networking, or business decisions.
- ViewModels coordinate screen behavior and own UI state. Use `@Observable`, keep explicit `@MainActor`, and prefer
  `send(_:)` as the UI event entry point while preserving established awaitable APIs where needed.
- UseCases represent meaningful operations or business rules. Do not create a pass-through UseCase only to satisfy the
  nominal layer sequence.
- Repositories own data access, mapping, and persistence abstractions where those boundaries add value.
- Managers provide transversal settings, credentials, sync, routing, device, and SDK services. A ViewModel may depend on a
  Manager directly when it represents UI-facing state or a system service and a UseCase would only forward the call.
- `APIClient` is the networking and streaming boundary. Feature-specific request and response mapping belongs near the
  repository or feature that owns the contract.
- Prefer protocol-backed dependencies and initializer injection at useful test seams.
- Keep asynchronous ownership and state mutation in the ViewModel rather than starting unowned work from Views.

## Feature Structure

- Organize feature code by ownership, creating only the Models, Repositories, UseCases, ViewModels, and Views folders the
  feature actually needs.
- Follow the nearest feature when choosing between a single file and a cohesive `Type+Concern.swift` split.
- Avoid moving code into `Core` merely because it is reusable once; promote it only when it has stable cross-feature
  ownership.
- Preserve persisted formats, deep links, App Group identifiers, and extension contracts unless migration and compatibility
  are explicitly part of the task.

## Structural Changes

- New Swift files require the standard repository header and correct target inclusion.
- Update `ARCHITECTURE.md` when targets, top-level ownership, layer responsibilities, or platform strategy intentionally
  change. It is an overview, not a source inventory.
- Apply `concurrency.instructions.md`, `code-style.instructions.md`, and platform/UI specs in addition to this file when
  their scopes are involved.
