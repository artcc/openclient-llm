---
description: "Use when writing or reviewing Swift formatting, naming, file layout, comments, MARK sections, localization, and readability."
applyTo: "**/*.swift"
---

# Swift Code Style

## General

- Preserve the style of nearby code and avoid unrelated cleanup.
- Prefer the smallest readable implementation. Keep functions cohesive, side effects explicit, and state handling
  exhaustive where practical.
- `.swiftlint.yml` is authoritative for enabled rules, severities, and numeric limits. Do not duplicate those values here.
- Use spaces rather than tabs, one statement per line, no trailing whitespace, and no more than one consecutive blank line.
- Wrap long declarations and argument lists consistently, usually one argument per line when multiline.
- Do not use force unwraps or force casts. Unwrap optionals with `guard let` or `if let`.
- Do not initialize optional stored properties with `= nil`.

## Files And Types

- Every Swift file starts with the repository copyright header used by nearby files. Use the owning target name for new
  target-specific files; preserve historical headers unless changing them is the task.
- Prefer one primary type per file named after that type. Tightly coupled supporting types and private helpers may remain
  together; cohesive large types may use `Type+Concern.swift` files.
- Prefer `struct` for value semantics and `enum` for closed states or options.
- Put protocol conformances and cohesive concerns in focused extensions when that improves navigation.
- Keep imports minimal and ordered consistently with nearby files.

## Organization

- Use `// MARK: -` sections only when they improve navigation; do not force sections into small files.
- Name sections for their purpose, such as `Properties`, `Init`, `View`, `Input functions`, `Tests`, or `Private`.
- Keep private helpers near the bottom when practical, without separating them from stored state they must access.
- Keep each section and extension focused on one concern.

## Naming And APIs

- Use UpperCamelCase for types and lowerCamelCase for properties, functions, and enum cases.
- Name actions with clear verbs and booleans with `is`, `has`, or `can` when semantically appropriate.
- Prefer domain terminology over ambiguous names or nonstandard abbreviations.
- Keep argument labels clear at call sites and associated-value labels where they improve meaning.
- Use early `guard` exits for preconditions and `switch` for exhaustive event or state handling.

## Comments And Safety

- Prefer expressive code over comments. Add short factual comments only for non-obvious intent, constraints, or invariants.
- Every `@unchecked Sendable` declaration requires a nearby comment documenting the actual synchronization or immutability
  invariant; test-only scope is not itself a safety proof.
- Do not leave tutorial commentary, stale implementation history, or comments that merely restate code.

## SwiftUI And Localization

- New or materially changed primary screens and reusable visual components need preview coverage, either locally or
  through a representative composed preview. Existing components without previews do not require unrelated retrofit work.
- Localize every user-facing source string. Write source strings in English.
- Use `String(localized:)` when an API requires `String`; localized literals are appropriate for APIs accepting
  `LocalizedStringKey` or `LocalizedStringResource`.
- Do not edit `Localizable.xcstrings` manually; translations are maintained separately by the project author.

## Dependencies

- Do not add or update packages without explicit user permission.
- Read the dependency set and versions from the Xcode project or package manifest rather than maintaining a duplicate list
  in documentation.
