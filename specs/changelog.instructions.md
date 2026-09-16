---
description: "Use when updating the CHANGELOG, adding entries for new features, bug fixes, or changes, deciding what to document, or reviewing changelog format."
applyTo: "**/CHANGELOG.md"
---

# Changelog Guidelines

## Format

The changelog follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

- Released headers use `## [MAJOR.MINOR.PATCH-build-N] - YYYY-MM-DD`. `MAJOR.MINOR.PATCH` follows SemVer; the build
  suffix is the project's release format, not SemVer build metadata.
- Each published build has its own section, including consecutive builds with the same marketing version.
- Use `## [Unreleased]` only when the user explicitly requests work not assigned to a build. When present, keep it above
  numbered releases.
- Within each release, use Keep a Changelog sections in this order and omit empty ones: `Added`, `Changed`,
  `Deprecated`, `Removed`, `Fixed`, `Security`.
- Dates use ISO 8601.

## Entry Style

- Use one concise sentence per bullet and one logical change per entry.
- Start with a noun or past-tense verb describing what changed, not who changed it
- Be specific: include the affected type, file, or feature name where helpful
- Do not mention PR numbers, commit hashes, or author names
- Group related entries under the same section, not by file or layer
- Do not introduce nested bullets; preserve them only where they already exist in historical releases

## What to Document

### Always document
- New user-facing features or UI changes
- New public types, protocols, or APIs added to Shared/
- Behaviour changes that affect the user experience
- Bug fixes visible to the user
- Security fixes
- Breaking changes to internal contracts (Repositories, UseCases, Managers)
- New platform support or deployment target changes
- New localization languages

### Do not document
- Internal refactors with no behaviour change (e.g. extracting a private method)
- Test additions or changes — unless fixing a previously untested bug
- SwiftLint or formatting-only changes
- Changes to `.gitignore`, CI scripts, or dev tooling (unless they affect contributors)
- Documentation-only changes (README, instructions files, prompts)

## When to Update

Update `CHANGELOG.md` when a feature or breaking change is implemented, a bug fix is confirmed, or a toolchain, platform,
or infrastructure change materially affects users or contributors. Do not add speculative or mid-implementation entries.

## Unreleased Section

When publishing entries already recorded under `Unreleased`, move them into a new numbered section. Retain an empty
`Unreleased` heading only if the user wants to keep that workflow. Never replace, merge into, or rename a historical
numbered section.

## Rules

- Do not rewrite historical entries merely for tone, punctuation, formatting, or to match newer conventions.
- Narrow historical corrections are allowed only when current code or an authoritative release artifact proves an entry
  factually wrong. Keep its release placement and change only the inaccurate wording.
- Numbered releases appear newest first, below `Unreleased` when present.
- Keep the introductory paragraph (Keep a Changelog + SemVer links) unchanged
- Do not copy historical inconsistencies into new entries or clean them up as part of unrelated work.
