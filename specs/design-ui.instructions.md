---
description: "Use when changing OpenClient SwiftUI visuals, interaction feedback, accessibility, localization, or visible UI states."
---

# OpenClient UI Design

## Contract

- These rules define OpenClient's stable visual and interaction constraints. UI changes must follow them or update this
  specification deliberately in the same change.
- Use the surrounding feature code for concrete details not specified here, such as exact icons, copy, spacing, navigation,
  and animation values. Those details do not override this contract.
- Do not use this specification as a reason to redesign unrelated UI.
- Accessibility, motion, preview, and state-presentation rules apply to new or materially changed surfaces; they do not
  require unrelated retrofits of untouched views.

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

- Keep new or changed motion restrained, interruptible, and tied to meaningful state changes. Respect Reduce Motion when
  adding repeating, spatial, or decorative animation, and avoid animation that destabilizes live content.
- Preserve native keyboard, pointer, focus, context-menu, and touch behavior for each platform.
- Keep interactive targets reachable and clearly labelled when their visible content does not communicate the action.
- Confirm destructive operations that can remove user data or cannot be undone. Use the platform-native destructive role
  and retain a clear cancellation path.

## Accessibility And Localization

- Localize every user-facing source string in English according to the repository localization rules.
- Use localized SwiftUI literals, `String(localized:)`, or `LocalizedStringResource` according to the receiving API. Keep
  user, model, server, tag, and filename data verbatim. Permission prompts are maintained in localized
  `InfoPlist.strings`; do not edit `Localizable.xcstrings` manually.
- Support VoiceOver with meaningful labels, values, hints when needed, logical reading order, and no interaction available
  only through visual position, color, hover, or gesture.
- Preserve sufficient contrast, Dynamic Type reflow, text selection where expected, and platform-appropriate target sizes.
- Do not encode meaning solely through color or animation.

## Model Parameter Editor

- Settings > Chat and each chat's Model Parameters action share the same modal editor and controls. The global editor saves
  installation defaults; the chat editor saves only conversation overrides. Save the four options together on Done; Reset
  clears the draft and takes effect on Done. Dismissing without Done discards edits. Explain whole-block precedence in the
  editor, and show conversation cost only when opened from a chat with available pricing and usage.

## Model Capability Editor

- Model Info includes an Automatic Capabilities toggle, enabled when no manual override exists. Automatic mode displays
  detected capabilities; manual mode starts from the effective selection and offers the existing capability flags except
  Text, which remains the fallback label rather than an editable switch.
- Edit a local draft in the detail sheet. Done saves the complete selection or removes the override in automatic mode;
  Cancel or dismiss discards edits. Explain server-specific precedence and that open chats keep their loaded capabilities.
- Update the Models list and its image/vision selectors after saving without refetching the catalog or notifying chats.
  Keep the server identity captured when the detail was opened so edits cannot be saved against a different server.
- The Automatic Capabilities toggle hosts a shared TipKit tip explaining manual selection. Show it only in automatic mode,
  invalidate it when the user switches to manual, and include it in the existing feature-tip eligibility reset.
- Sort capability labels in the Models list and detail (including manual toggles) using localized comparison of their
  translated labels.

## Advanced Server Settings

- Settings > Server opens Advanced Server Settings as a native shared sheet, with Custom Headers as its initial section.
- Each row edits a name and an initially concealed, revealable value, and supports explicit deletion. Add Header creates
  a draft row. Show validation errors beside the affected fields and disable Done while the draft is invalid.
- Cancel or dismiss discards modal edits. Done copies valid edits into the Server draft; the existing Server Save action
  persists URL, API key, and headers together, preserving header name capitalization and row order even when effective
  values are unchanged. Explain this two-step behavior in the sheet. Test Connection uses that draft.
- Applying changed headers clears the saved/connection status. A failed save retains the draft and the existing persistence
  error/retry presentation. Editing server configuration cancels checks and rejects their stale completions.

## Visible States

- New or materially changed primary surfaces must distinguish loading, unavailable, empty, and failed states rather than
  presenting unexplained blank content. Structural subviews may intentionally render no content.
- Reuse the feature's existing loading, empty, error, disconnected, disabled, and in-progress presentations.
- Keep recoverable errors near their context with an available recovery action when one exists; reserve blocking
  presentation for decisions that require it.
- Do not expose raw implementation errors or credentials in user-facing UI.
