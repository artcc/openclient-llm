---
description: "Use when writing async code, choosing actor isolation, managing tasks or cancellation, applying Sendable, or reviewing thread safety."
---

# Swift Concurrency

Apply these rules to new concurrency code and to behavior being materially changed, without expanding the task into
unrelated refactoring.

## Configuration And Isolation

- Read default actor isolation and strict-concurrency settings from each target's current Xcode configuration. Shared code
  inherits the settings of every target that compiles it; do not generalize one target's defaults to the whole project.
- Keep ViewModels explicitly `@MainActor` even when an app target supplies that default. Their observable state is UI-bound.
- Use `@Observable`, not `ObservableObject` or `@Published`.
- XCTest classes that synchronously access app-isolated production types must be explicitly `@MainActor`; follow the
  existing suite's class-level convention.
- Do not add isolation annotations solely to silence diagnostics. Identify which state owns the operation and which values
  cross isolation boundaries.

## Choosing An Isolation Model

- Keep Views, ViewModels, and UI-owned state on `MainActor`.
- Use `nonisolated` only when a declaration must be callable or constructible outside its enclosing actor and does not
  access actor-owned state. It changes isolation, not the executor on which synchronous work runs.
- Use `@concurrent` only for substantial asynchronous work that must leave caller isolation. Inputs and results crossing
  that boundary must be safely transferable.
- Prefer immutable `Sendable` value types for data that crosses isolation boundaries.
- Use an actor for mutable state requiring asynchronous serialization, or `MainActor` when that state is UI-owned.
- Use a proven thread-safe primitive or framework API only when its calling semantics fit the operation and the invariant
  can be documented.

## Tasks And Cancellation

- Prefer structured concurrency such as direct `await`, `async let`, and task groups over unstructured tasks.
- Use SwiftUI `.task` and `.task(id:)` for work owned by a view lifecycle.
- A `Task` inherits its creation context. Create one only to bridge a synchronous entry point or to model independently
  owned work; do not wrap every ViewModel event in a task from the View.
- Store long-lived tasks when later events must cancel, replace, or await them. Define their owner and cleanup path, and
  avoid ownership cycles.
- Treat cancellation as control flow. Check it around expensive work and relevant suspension points, exit repeating loops,
  and do not map `CancellationError` to a user-facing failure.
- Avoid detached tasks unless loss of actor context, priority inheritance, task-local values, and parent cancellation is an
  explicit requirement.

## Reentrancy

- Actor isolation prevents data races, not stale completions or business-ordering races.
- Assume actor state may change across every `await`.
- Complete related mutations before suspension when possible. Otherwise capture an identity, generation, or state snapshot
  and validate it before committing the result.
- Cancel superseded operations or ignore their stale completions.

## Sendable

- Prefer checked `Sendable` conformance. A type's stored values and mutation model must support its conformance in every
  target and isolation domain where it is used.
- Closures crossing isolation boundaries must be `@Sendable`, and their captures must be safely transferable.
- Use `@unchecked Sendable` only when no checked design expresses a real, reviewed safety invariant.
- Document immediately above each `@unchecked Sendable` declaration why every mutable access is serialized or why the
  complete stored state is immutable and backed by APIs documented as thread-safe.
- Keep `nonisolated(unsafe)` narrowly scoped and covered by the same explicit invariant. It is not a substitute for
  synchronization.

## Test Doubles

- A mock is not safe merely because it is used by tests or because its owning XCTest class is `@MainActor`.
- Prefer actor-isolated mocks, immutable value doubles, or synchronization primitives when callbacks or concurrent tasks
  can access mutable test state.
- An `@unchecked Sendable` mock must state and enforce a real invariant, such as all mutable access being confined to one
  actor or protected by a lock. Ensure protocol methods and spawned tasks cannot violate that invariant.
- Use deterministic coordination through controllable dependencies, continuations, expectations, actor gates, or other
  bounded signals. Do not rely on arbitrary sleeps.

## Review Checklist

- Isolation matches ownership and target configuration.
- Values crossing boundaries are safely transferable.
- Tasks have intentional ownership, cancellation, and error handling.
- State observed before suspension is revalidated when needed.
- Every unchecked conformance has a complete, enforceable safety invariant.
