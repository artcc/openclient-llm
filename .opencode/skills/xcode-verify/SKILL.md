---
name: xcode-verify
description: Use when building, running, testing, linting, or verifying the openclient-llm Xcode project, including fixing compiler, test, or SwiftLint failures.
---

# Xcode Verification

Use this skill for Xcode operations in `openclient-llm`. After implementation work, ask the user before compiling,
checking SwiftLint, or running tests, as required by `AGENTS.md`. A direct request to build, run, lint, or test is approval
for that requested operation.

## Setup

1. Before the first XcodeBuildMCP build or test call, use `session_show_defaults`.
2. Before building, create `Secrets.xcconfig` from the setup template in `README.md` if it is missing; never overwrite it.
3. Prefer XcodeBuildMCP and use the project, scheme, and simulator defaults from `.xcodebuildmcp/config.yaml`. Only repair
   defaults that are missing or wrong.
4. Disable code signing for builds and tests with `CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO`. For tests, add
   `-test-timeouts-enabled YES -maximum-test-execution-time-allowance 120`.
5. If an MCP request fails or times out, use `xcodebuild` with the current project, scheme, and destination from the
   session defaults or `.xcodebuildmcp/config.yaml`; preserve the same signing and timeout arguments.

## Operations

- **Build iOS:** use `build_sim`.
- **Run iOS:** use `build_run_sim`; it boots, installs, and launches the app without separate simulator setup.
- **Build macOS:** use `build_macos`.
- **Run macOS:** use `build_run_macos`.
- **Focused tests:** use `test_sim` with `-only-testing` for the smallest relevant test class or target.
- **Full tests:** use `test_sim` for the complete iOS suite. Shared-code changes require the full suite when verification
  is approved.
- **SwiftLint:** inspect build output because SwiftLint runs as part of the app builds.

Do not erase or reset simulators. Do not modify source code merely to run the app unless the user also asks to fix a
failure.

## Failure Handling

1. Read every compiler error, failed test, and SwiftLint warning in context before changing code.
2. Fix root causes rather than suppressing checks. Never skip tests, disable SwiftLint rules, add `swiftlint:disable`, or
   modify `.swiftlint.yml` unless the user explicitly requests the configuration change.
3. After a fix, rerun the smallest operation that proves it. Run broader verification only when required by `AGENTS.md`
   and approved by the user.
4. Run `git diff --check` before reporting completion after source changes.

## Completion Criteria

- Report exactly which builds, launches, lint checks, or tests ran and their result.
- For tests, report the available total and failures without listing every passing test unless requested.
- State any verification that could not run and why.
