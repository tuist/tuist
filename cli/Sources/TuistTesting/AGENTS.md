# TuistTesting (CLI Module)

This module provides testing helpers used by CLI modules and tests.

## Responsibilities
- Provide test-only helpers and fixtures (e.g., `MockFatalError`, test data extensions).
- Supply data builders for HTTP responses and fixtures.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistSupport/AGENTS.md

## Invariants
- Test helpers must avoid mutating global process environment.
