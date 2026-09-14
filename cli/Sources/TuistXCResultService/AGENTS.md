# TuistXCResultService (CLI Module)

This module provides XCResult handling helpers for test results.

## Responsibilities
- Model test results (`TestCase`, `TestModule`, `TestStatus`) and failures.
- Provide structures to parse and surface xcresult data.
- Read the bundle's `xccov` line coverage on its own (`parseCoverage`), separately from `parse`, so callers that only need test results (the stress gate, selective-testing target names) never spawn `xccov`. The upload boundary attaches it to the `TestSummary` once per run, in every processing mode: the server may parse the tests, but only the client owns the checkout the coverage paths are relative to. A coverage read failure is reported as a warning and dropped: coverage only enriches a run.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistGenerator/AGENTS.md

## Invariants
- Test results track status, duration, and structured failures for reporting.
- The parsers live in the shared `XCResultParser` package under `server/native/xcresult_nif`, so the CLI and the server's xcresult processor read bundles the same way.
