---
description: "Use when changing OpenClient SwiftUI visuals, interaction feedback, accessibility, localization, or visible UI states."
applyTo: "{openclient-llm/Shared/**/Views/**/*.swift,openclient-llm-macOS/**/*.swift,WidgetsShared/**/*.swift}"
---

# OpenClient UI Design

## Contract

- These rules define OpenClient's stable visual and interaction constraints. UI changes must follow them or update this
  specification deliberately in the same change.
- Use the surrounding feature code for concrete details not specified here, such as exact icons, copy, spacing, navigation,
  and animation values. Those details do not override this contract.
- Do not use this specification as a reason to redesign unrelated UI.

## Native Visual Language

- Prefer native SwiftUI controls, containers, materials, interactions, and platform conventions over custom replicas.
- Use Liquid Glass where the current hierarchy calls for a distinct surface or interactive control.
- Do not add glass to navigation, toolbar, tab, sidebar, or other system chrome that already supplies it.
- Avoid nested or overlapping glass surfaces that create double glass. Group related glass elements only when their
  composition requires it.
- Apply interactive glass only to interactive elements; preserve legibility over changing backgrounds and appearances.
- Use semantic system colors and semantic asset colors. Do not hardcode RGB or hexadecimal colors in views.
- Follow the system appearance. Do not force light or dark mode.

## Typography And Symbols

- Use semantic system text styles for the interface by default.
- Keep Poppins as a selective display accent where OpenClient already establishes it; do not turn it into the default UI
  typeface.
- Ensure custom typography scales relative to a Dynamic Type text style and does not clip at accessibility sizes.
- Prefer SF Symbols for generic actions, status, and concepts. Preserve custom artwork for OpenClient and provider branding.

## Interaction

- Keep motion restrained, interruptible, and tied to meaningful state changes. Respect Reduce Motion and avoid animation
  that destabilizes live or frequently updating content.
- Preserve native keyboard, pointer, focus, context-menu, and touch behavior for each platform.
- Keep interactive targets reachable and clearly labelled when their visible content does not communicate the action.
- Confirm destructive operations that can remove user data or cannot be undone. Use the platform-native destructive role
  and retain a clear cancellation path.

## Accessibility And Localization

- Localize every user-facing source string in English according to the repository localization rules.
- Support VoiceOver with meaningful labels, values, hints when needed, logical reading order, and no interaction available
  only through visual position, color, hover, or gesture.
- Preserve sufficient contrast, Dynamic Type reflow, text selection where expected, and platform-appropriate target sizes.
- Do not encode meaning solely through color or animation.

## Visible States

- Never leave a screen blank while data is loading, unavailable, empty, or failed.
- Reuse the feature's existing loading, empty, error, disconnected, disabled, and in-progress presentations.
- Keep recoverable errors near their context with an available recovery action when one exists; reserve blocking
  presentation for decisions that require it.
- Do not expose raw implementation errors or credentials in user-facing UI.
