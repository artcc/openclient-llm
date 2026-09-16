---
description: "Use when adding or changing XCTest coverage, test doubles, fixtures, async synchronization, or test organization."
applyTo: "openclient-llm-test/**/*.swift"
---

# Testing

## Scope And Boundaries

- Add focused tests for changed behavior at the smallest useful boundary. Do not add ceremonial tests for pass-through
  types or test private implementation details.
- Test ViewModels through events and observable state, UseCases through business outcomes, Repositories through mapping and
  persistence boundaries, and Managers through their public contracts.
- Unit tests must isolate external services with protocol-backed doubles. Real network or service integration requires an
  explicit task scope, opt-in configuration, and safeguards against accidental CI execution.
- Mirror production feature or core ownership in the test directory. Put reusable doubles in `Mocks/`; keep a small,
  single-use helper private to its test file.
- Large test types may use cohesive `Type+Concern.swift` splits or focused XCTest classes.

## New Test Conventions

Apply these conventions to new tests and substantially rewritten tests; do not churn unrelated existing tests solely for
conformance:

- Test files and classes use `<TypeUnderTest>Tests`.
- Test methods use `test_<method>_<scenario>_<expectedResult>()` with meaningful domain terms.
- Organize setup, action, and assertions as Given-When-Then, using `// Given`, `// When`, and `// Then` when the separation
  improves readability.
- Keep each test focused on one behavioral intent, with all assertions needed to describe that outcome.
- Use `@testable import openclient_llm` for internal production APIs.
- Mark XCTest classes `@MainActor` where required by production isolation and follow the suite's established class-level
  annotation pattern rather than annotating individual methods inconsistently.

## Test Doubles

- Prefer configurable protocol-backed doubles with explicit defaults that fail clearly when required behavior is not set.
- Record only the calls and values needed by assertions.
- Reset or recreate mutable state per test; do not depend on test execution order.
- Follow `concurrency.instructions.md` for `Sendable`. Test-only use and `@MainActor` on the XCTest class do not by themselves
  make a mutable mock safe.

## Async And Concurrent Tests

- Prefer direct `async` test methods for async APIs.
- Synchronize deterministically with controllable dependencies, continuations, XCTest expectations, actor gates, clocks,
  or bounded signals appropriate to the behavior. Expectations remain valid when testing callbacks or explicit events.
- Avoid arbitrary sleeps, timing guesses, unbounded polling, and reliance on scheduler order.
- Fulfill continuations and expectations exactly once, bound waits with meaningful timeouts, and clean up long-lived tasks.
- Exercise cancellation, stale-result rejection, and ordering when those behaviors are part of the contract.

## Reliability

- Keep tests independent, repeatable, and free of production user settings, Keychain namespaces, App Group data, or
  persistent files.
- Persistence and Keychain tests may use isolated stores, synthetic values, and unique namespaces. Remove only data created
  by that test.
- Avoid force unwraps in test code; use XCTest unwrapping and explicit failures.
- Assert public outputs and meaningful side effects rather than incidental call sequences unless ordering is itself required.

## Validation

- Ask the user before running any test, build, linter, or related validation command.
- Once authorized, run the smallest relevant test target or class first. Broaden validation only when the change crosses
  shared boundaries or focused results justify it.
- Report skipped validation and residual coverage risks explicitly.
