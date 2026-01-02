# TuistXCResultService (CLI Module)

This module provides XCResult handling helpers for test results.

## Responsibilities
- Model test results (`TestCase`, `TestModule`, `TestStatus`) and failures.
- Provide structures to parse and surface xcresult data.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistGenerator/AGENTS.md

## Invariants
- Test results track status, duration, and structured failures for reporting.
