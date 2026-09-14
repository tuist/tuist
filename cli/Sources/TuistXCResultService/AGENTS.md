# TuistXCResultService (CLI Module)

This module provides XCResult handling helpers for test results.

## Responsibilities
- Model test results (`TestCase`, `TestModule`, `TestStatus`) and failures.
- Provide structures to parse and surface xcresult data.
- Attach the bundle's `xccov` line coverage to the parsed `TestSummary` (`parse`) and expose it on its own (`parseCoverage`) for the remote path, where the server parses the tests but the client still owns the checkout the coverage paths are relative to. A coverage read failure is logged and dropped: coverage only enriches a run.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistGenerator/AGENTS.md

## Invariants
- Test results track status, duration, and structured failures for reporting.
- The parsers live in the shared `XCResultParser` package under `server/native/xcresult_nif`, so the CLI and the server's xcresult processor read bundles the same way.
