---
description: "Use when changing OpenClient chat messages, attachments, composer, streaming presentation, Markdown, actions, or scrolling."
applyTo: "{openclient-llm/Shared/Features/Chat/**/*.swift,openclient-llm/Shared/Core/Utils/Markdown*.swift,openclient-llm/Shared/Core/Utils/RenderedMarkdown.swift,openclient-llm-macOS/Views/MenuBarChatView.swift}"
---

# OpenClient Chat Visual Style

## Scope

- This specification defines stable chat-specific behavior. A deliberate change to that behavior must update this file in
  the same change.
- Apply `design-ui.instructions.md`. Use the Chat implementation only for concrete controls, symbols, strings, spacing, and
  navigation details not specified by either contract.
- Keep the conversation content-first, readable, and visually stable during updates.

## Conversation Layout

- Keep messages in an adaptable readable column: use available compact width without allowing lines to become excessively
  long in wide windows.
- Distinguish roles through stable composition rather than duplicated decoration.
- Present user messages on the trailing side in accent-tinted glass with legible foreground content.
- Present assistant messages on the leading side without a message bubble; rendered content sits directly in the
  conversation column.
- Keep message metadata visually secondary but available on touch, keyboard, and pointer platforms. Do not make timestamps,
  usage, status, or other meaningful metadata hover-only.

## Message Content And Attachments

- Render user source text as entered. Render completed assistant content through `RenderedMarkdown`, preserving support for
  headings, paragraphs, emphasis, links, lists and task lists, quotations, rules, code, tables, images, footnotes, and the
  supported inline subscript and superscript forms.
- During streaming, favor immediate stable text over repeatedly reparsing final Markdown. Switch to final Markdown when the
  response completes.
- Keep code and other horizontally constrained content readable and selectable without widening the conversation column.
- Present attachments as part of their message or pending composer state. Preserve aspect ratio, recognizable previews,
  loading/failure feedback, and accessible descriptions.
- Do not invent attachment types, previews, or controls that the current capabilities do not support.

## Message Actions

- Expose actions only when they are valid for the message state, role, content, platform, and enabled capability.
- Preserve access to implemented actions through the interaction patterns already used by each platform; do not rely on
  hover or an undiscoverable gesture as the only route.
- Keep destructive message or conversation actions confirmed according to the general UI specification.
- Action feedback must not shift message content or obscure streaming state.

## Composer

- Keep the composer anchored to the conversation and clear of the keyboard and safe areas.
- Adapt its arrangement as text, attachments, tools, speech, and available width change; do not force one fixed horizontal
  layout across iPhone, iPad, and macOS.
- Let text entry grow within the feature-defined bounds while keeping primary controls reachable.
- Reflect action availability explicitly. Sending, stopping, attaching, speaking, and tool-related controls must match the
  current model selection, input, permission, capability, and streaming state.
- Preserve draft content and pending attachments across incidental layout or focus changes.

## Streaming Stability

- Show an immediate, localized waiting state until content arrives, then transition to the streaming presentation.
- Group streamed UI updates rather than publishing every token independently; the exact debounce interval is an
  implementation detail. Do not add per-token container animations, repeated Markdown layout, or lazy-row behavior that
  destabilizes scrolling.
- Keep message identity and row layout stable throughout reasoning, tool execution, answer generation, cancellation, error,
  and completion.
- Finalization must remove transient streaming presentation and render the final assistant Markdown without losing content.

## Scroll Follow

- Follow the bottom for initial entry and active responses only while follow mode is attached.
- Detach immediately when the user deliberately reads history, preserve their position, and expose an explicit route back
  to the latest content.
- Resume follow when that route is used or a new response starts.
- Drive automatic positioning from semantic chat and scroll phases, not from message visibility or continuously changing
  geometry. Visibility may inform presentation such as date context, but not automatic scrolling.
- Preserve the main conversation's native scroll and keyboard-dismiss behavior. Horizontal code, table, and attachment
  scrollers may hide indicators when their content and interaction remain discoverable.

## Chat Accessibility

- For new or materially changed message presentation, maintain a logical reading order and expose the meaningful role,
  content, state, and available actions to assistive technologies without duplicating the full visual tree.
- Group any streamed accessibility announcements; do not announce every fragment.
- Ensure Dynamic Type can reflow messages, metadata, Markdown, attachments, and composer controls without clipping or
  hiding actions.
- Localize all chat labels, status, errors, metadata, and accessibility text; this specification does not define their copy.
