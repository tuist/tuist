# TuistXCResultService (CLI Module)

This module provides XCResult handling helpers for test results.

## Responsibilities
- Model test results (`TestCase`, `TestModule`, `TestStatus`) and failures.
- Provide structures to parse and surface xcresult data.
- Read the bundle's `xccov` line coverage on its own (`coveredFilePaths` / `parseCoverage`), separately from `parse`, so callers that only need test results (the stress gate, selective-testing target names) never spawn `xccov`. Coverage is processed where the bundle is processed: in remote mode the upload boundary writes an `XcodeCoverageManifest` (checkout root spellings, the covered files' Git blob ids, partial-run flag) into the bundle and the server's macOS processor reads the coverage; in local mode the client reads it with the same shared parser, streamed to a file of one JSON object per source file (`parseCoverage(path:manifest:into:)`, memory flat in the bundle's size), then `TuistKit.CoverageUploadService` DEFLATE-compresses it and either sends it inline with the run (up to the server's `inline_threshold_bytes`, from `GET .../tests/coverage/settings`) or PUTs it to a signed URL from `POST .../tests/coverage/uploads` under a client-chosen run id and references it with `xcode_coverage_storage_key`. The manifest is only built when the `COVERAGE` client feature flag is on (`TUIST_FEATURE_FLAG_COVERAGE=1`, early access), the bundle has coverage and the upload is on (`Tuist.swift` `testInsights: .testInsights(coverage: .coverage(upload:))`, overridden by `TUIST_COVERAGE_UPLOAD`). A coverage read failure is reported as a warning and dropped: coverage only enriches a run.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistGenerator/AGENTS.md

## Invariants
- Test results track status, duration, and structured failures for reporting.
- The parsers live in the shared `XCResultParser` package under `server/native/xcresult_nif`, so the CLI and the server's xcresult processor read bundles the same way.
- `TestExecutionModes` (shared package) records whether a run executed its tests in parallel or serially, per target: `TuistKit.TestExecutionModeResolver` resolves it from `-parallel-testing-enabled` and the xctestrun's `ParallelizationEnabled` (from `-xctestrun`, `-testProductsPath` or the derived data's build products) and writes `tuist_execution_modes.json` into the result bundle before the upload; the shared parser applies the file to the summary (`applying(executionModes:)`, run and per module), so the local-mode payload and the server's processor record the same `execution_mode`. Without an xctestrun or the flag nothing is guessed.
