---
description: "Use when deciding how OpenClient SwiftUI code and behavior are shared or adapted across iOS, iPadOS, and macOS."
applyTo: "{openclient-llm/Shared/**/Views/**/*.swift,openclient-llm-macOS/**/*.swift,WidgetsShared/**/*.swift}"
---

# OpenClient SwiftUI Multiplatform Structure

## Contract

- The Xcode project defines actual target membership; this specification defines how shared and platform-specific UI must
  be structured. Keep both aligned in every architectural change.
- Do not introduce a new navigation hierarchy, shared abstraction, or platform behavior unless the requested change also
  updates the applicable specification and structural documentation.
- Verify behavior on every target affected by a shared view; visual parity is not a substitute for native behavior.

## Shared And Platform-Specific Code

- Shared app UI and feature code lives under `openclient-llm/Shared/` and is compiled by the iOS and macOS app targets.
- Keep genuinely platform-specific app, commands, menu bar, lifecycle, and UI code in its platform target directory.
- Keep a view shared when its structure and behavior are substantially the same. Use a small `#if os(...)` branch for a
  localized platform difference.
- Split platform implementations when composition or interaction is fundamentally different. Do not accumulate broad
  conditional branches inside a nominally shared view.
- Feature-owned components stay with their feature. Move a component to shared core only when it has real cross-feature
  use.

## Deliberate Adaptation

- Prefer native SwiftUI APIs available to all affected deployment targets.
- Choose controls, presentation, density, focus, keyboard handling, pointer behavior, menus, commands, sheets, popovers,
  toolbars, and window behavior deliberately for each platform.
- Let iPadOS adapt to size class, input method, and available width; do not treat it as either a stretched iPhone or a Mac.
- Preserve system-provided chrome and behavior. Do not recreate it in shared content or layer custom Liquid Glass over it.
- Guard platform-only APIs at the narrowest useful scope and keep unsupported code out of the other target's compilation.
- Share user-visible capability where appropriate, but allow platform-native routes to that capability to differ.

## View Responsibilities

- Views render current observable state and send user events through the feature's established interfaces.
- Keep platform presentation decisions in views or focused platform adapters; keep shared domain behavior independent of
  platform UI.
- Represent loading, empty, error, disabled, and in-progress states explicitly, following the general UI specification.
- Preserve state across adaptive layout changes unless the current feature intentionally resets it.

## Previews

- Provide preview coverage for primary screens and reusable visual components, in the same file or an existing dedicated
  preview file.
- Cover the meaningful states and layout variants needed to understand a component, not an exhaustive snapshot matrix.
- Include representative compact and wide contexts when adaptation is part of the component's responsibility.
- Platform adapters and infrastructure-only views may rely on a composed parent preview when that exercises their UI.
- Keep previews deterministic, lightweight, localized through source strings, and independent of live services or secrets.
