---
description: "Use when adding anything to CHANGELOG.md, choosing a release version or build number, or synchronizing app, TestFlight, and Remote Config version references."
applyTo: "{CHANGELOG.md,README.md,TestFlight/*.txt,config.json,config-dev.json,openclient-llm.xcodeproj/project.pbxproj}"
---

# Release Version Workflow

Read this specification together with `changelog.instructions.md` whenever a request adds or changes a changelog entry.
A numbered changelog release is an atomic version update: keep active app-version references in sync without changing
historical release data.

## Required Questions

Before a numbered release edit, inspect the latest numeric changelog header and explicitly ask for any missing value:

1. Marketing version (`MAJOR.MINOR.PATCH`).
2. Build number.

Include the current values as context. Do not infer or increment either value, and do not edit until both are known.

If the user explicitly wants an `Unreleased` entry, confirm that choice instead of requiring a numeric version and build.
An `Unreleased` entry does not change TestFlight notes or any active app-version reference.

## Changelog Release

- Format a numbered header as `## [MAJOR.MINOR.PATCH-build-N] - YYYY-MM-DD`.
- Use the exact version and build chosen by the user; normalize a bare build number such as `78` to `build-78`.
- Use the current date unless the user supplies a different release date.
- Follow `changelog.instructions.md` for section order, entry wording, and what belongs in the changelog.
- Create a new section for every published build, even when its marketing version matches the previous build.
- Never replace, rename, merge into, or otherwise repurpose a historical build section.

## Active Version Synchronization

For every numbered release, locate and synchronize the chosen marketing version in:

1. The new release header in `CHANGELOG.md`, together with the chosen build number.
2. Every existing `TestFlight/*.txt` file, following the TestFlight rules below.
3. `MARKETING_VERSION` in every shipping app and extension target, for Debug and Release configurations.
4. Both the badge URL and alt text of the version badge in `README.md`.
5. The iOS and macOS `latest_version` values in existing local `config.json` and `config-dev.json` files, even when update
   notifications are disabled.

Do not rely only on a blind repository-wide replacement. Search for the previous active version and classify each match so
historical releases and unrelated version numbers remain unchanged.

## Values That Must Remain Stable

- Keep every shipping target's checked-in `CURRENT_PROJECT_VERSION` stable at `1`. Deployment supplies the published
  build number; the user-supplied build belongs in the changelog header.
- Keep the unit-test target's `MARKETING_VERSION` at `1.0.0`.
- Do not synchronize release versions into tests or mocks.
- Do not change historical changelog headers or entries.
- Do not change unrelated project, schema, backup-format, deployment-target, package, or fixture versions.
- Keep `config.json` and `config-dev.json` ignored by Git. Never force-add them to a commit.

## TestFlight Release Notes

Update every existing `TestFlight/*.txt` file for each numbered build; do not ask a separate question or create locale
files. The actual format is a localized greeting, a block of `•` bullets for the current build, and localized closing
paragraphs, with blank lines between those parts. Preserve the greeting, closing, language, bullet character, punctuation,
and layout; replace only the release bullet block. Do not add version headings, build headings, or release history.

Adapt changelog entries into concise user-facing benefits rather than copying implementation details. Keep the localized
minor-fixes bullet when it accurately summarizes the build or complements substantive bullets.

## Remote Config Decisions

The local `config.json` and `config-dev.json` files mirror Remote Config. Synchronize only their `latest_version` values by
default; do not assume production and development behavior should match.

Explicitly ask before enabling `force_update` and identify whether it applies to production, development, or both. Also
ask before any destructive banner change: disabling, replacing, removing content, or changing `dismiss_banner_key`. Keep
all other flags and banner fields unchanged unless the user requests them. Never replace version text inside banner copy
mechanically.

### New banner questions

For a confirmed new banner, collect any missing message, platforms, target config files, activation state, localized copy,
CTA action, and URL when applicable. Generate a stable release-and-message `dismiss_banner_key` unless supplied; do not
change the key merely to re-show unchanged content.

### Valid banner actions

Use only the exact, case-sensitive actions `close`, `open_url`, `feedback`, and `tip`; unknown values break decoding.
`open_url` requires a valid HTTP(S) URL. For other actions, use an empty `url` unless explicitly preserving one. An empty
`cta` hides the action button.
