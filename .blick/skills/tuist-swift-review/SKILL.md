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

## 2. Testing framework — Swift Testing, not XCTest

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
