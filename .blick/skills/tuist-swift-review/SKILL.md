---
name: tuist-swift-review
description: Project-specific PR-review rules for the tuist/tuist Swift codebase (cli). Focuses on the things only this repo knows — preferring value types, the testing framework choice, and migration of XCTest to Swift Testing.
---

# Tuist Swift Review

This skill is intentionally narrow. **Generic Swift style, formatting,
naming, and lint hygiene are already covered by SwiftFormat / SwiftLint
in CI — do not flag those.** Focus on the rules below.

For each finding, cite `path:line` and quote the relevant snippet.

---

## 1. Prefer structs over classes

Default to `struct` for new types. Reach for `class` only when reference
semantics, identity, inheritance, or `deinit` are actually required.

### Flag

- **A new `class` declaration that has no stored mutable identity, no
  inheritance, no `deinit`, and is not bridged to an Objective-C / Cocoa
  API.** Recommend converting it to a `struct`. **Severity: medium.**

### Do not flag

- Existing classes left unchanged by the diff.
- Classes that subclass a framework type (`NSObject`, `XCTestCase`,
  `Operation`, etc.) or conform to a protocol that requires reference
  semantics.
- Types that genuinely need reference identity (caches, long-lived
  coordinators, actors-with-state-shared-by-reference).
- **`final class` declarations whose `Sendable` conformance is backed by
  a stored `Synchronization.Mutex<State>` (or another `~Copyable`
  synchronization primitive).** `Mutex` cannot be a stored property of a
  `Copyable` struct — the compiler emits `stored property '...' of
  'Copyable'-conforming struct '...' has non-Copyable type 'Mutex<...>'`
  — and a `~Copyable` struct cannot be captured by a `@Sendable` closure.
  A `final class` with the `Mutex` and `Sendable` conformance is the
  correct expression of this pattern.

## 2. Avoid `@unchecked Sendable`

`@unchecked Sendable` opts out of the compiler's concurrency safety
checks and shifts the burden of correctness onto every reader. Prefer
proper synchronization primitives that the compiler can verify.

### Flag

- **A newly added `@unchecked Sendable` conformance** (whether on a
  `final class`, a `struct`, or an extension). Recommend one of:
  - `Mutex<State>` from `Synchronization` (Swift 6.0+) for shared
    mutable state — wrap the state in a single `Mutex` and expose
    `withLock { ... }` accessors.
  - `OSAllocatedUnfairLock<State>` from `os` for Apple-only code where
    `Mutex` is not yet available.
  - An `actor` when the type can be reached only from `async` contexts.
  - Make the type a value type with only `Sendable` stored properties so
    the compiler can synthesize `Sendable` itself.

  **Severity: medium.**

### Do not flag

- Existing `@unchecked Sendable` conformances the diff does not touch.
- Types that bridge to a framework requirement the compiler genuinely
  cannot reason about (e.g. wrapping a non-Sendable Objective-C class
  whose thread-safety the author has verified). Require an explanatory
  comment naming the invariant the author is asserting.

When suggesting `Mutex`, point at
`cli/Sources/TuistAppleArchiver/AppleArchiver.swift` for the in-tree
usage pattern: `let state = Mutex(State())` plus
`state.withLock { ... }`.

## 3. Testing framework — Swift Testing, not XCTest

New tests must be written with **Swift Testing** (`import Testing`,
`@Test`, `#expect`, `#require`). XCTest is legacy in this repo.

When a diff **modifies** an existing XCTest case (i.e. the test file
already uses `XCTestCase` / `func testXxx()` and the PR changes one of
those tests), the test should be **rewritten in Swift Testing as part of
the same change** rather than patched in place. Touching a test is the
moment to migrate it.

### Flag

- **A newly added test file or test function that uses `XCTestCase` /
  `XCTAssert*` / `func testXxx()`.** Recommend Swift Testing.
  **Severity: high.**
- **A modified XCTest test that was edited but not migrated to Swift
  Testing.** Ask the author to rewrite the touched test(s) using
  `@Test` / `#expect` / `#require`. **Severity: medium.**
- **Mixing `XCTAssert*` calls inside a Swift Testing `@Test`** (or vice
  versa). Pick one framework per test.

### Do not flag

- Pre-existing XCTest tests that the diff does not touch.
- XCTest-only APIs that have no Swift Testing equivalent yet (e.g.
  `XCUITest` UI automation) — leave those on XCTest.
- Test helpers/fixtures that aren't themselves test cases.

When suggesting the migration, point at the project's Swift Testing
pattern (see `cli/AGENTS.md`): use `@Test(.inTemporaryDirectory)` and
`FileSystem.temporaryTestDirectory` for tests that need a temp dir, and
`#require` for unwrapping.
