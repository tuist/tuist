---
name: compare-test-runs
description: Compares two test runs to identify new failures, newly flaky tests, fixed tests, and duration regressions. Can be invoked with test run IDs, dashboard URLs, or branch names.
---

# Compare Test Runs

## Quick Start

You'll typically receive two test run identifiers. Follow these steps:

1. Run `tuist test show <id> --json` for both base and head test runs.
2. Run `tuist test case run list --test-run-id <id> --json` to get individual test case results.
3. Compare failures, flaky tests, durations, and overall status.
4. Inspect failing test cases with `tuist test case run show <id> --json`.
5. Summarize findings with actionable recommendations.

## Step 1: Resolve Test Runs

### If base/head are test run IDs or dashboard URLs

Fetch each directly:

```bash
tuist test show <base-id> --json
tuist test show <head-id> --json
```

### If base/head are branch names

List recent test case runs on each branch to identify test run IDs:

```bash
tuist test case run list --json --page-size 5
```

Look at `test_run_id` fields to find recent test runs per branch.

### Defaults

- If no base is provided, use the project's default branch (usually `main`).
- If no head is provided, detect the current git branch.

## Step 2: Compare Top-Level Metrics

After fetching both test runs, compare:

| Metric | What to check |
|---|---|
| `status` | Flag if base passed but head failed |
| `duration` | Flag if head is >10% slower |
| `total_test_count` | Note if test count changed (new or removed tests) |
| `failed_test_count` | Compare failure counts |
| `flaky_test_count` | Compare flaky counts |
| `avg_test_duration` | Flag significant changes |

## Step 3: Get Test Case Results

Fetch test case runs for both test runs:

```bash
tuist test case run list --test-run-id <base-test-run-id> --json --page-size 100
tuist test case run list --test-run-id <head-test-run-id> --json --page-size 100
```

Match test cases by their `name` + `module_name` + `suite_name` across both runs.

## Step 4: Classify Changes

Group test cases into categories:

1. **New failures**: Tests that passed in base but failed in head.
2. **Fixed tests**: Tests that failed in base but passed in head.
3. **Newly flaky**: Tests not flaky in base but flaky in head.
4. **No longer flaky**: Tests that were flaky in base but stable in head.
5. **New tests**: Tests present in head but not in base.
6. **Removed tests**: Tests present in base but not in head.
7. **Duration regressions**: Tests with >50% duration increase.

## Step 5: Inspect Failures

For each new failure, get detailed information:

```bash
tuist test case run show <test-case-run-id> --json
```

Key fields to examine:
- `failures[].message` -- the assertion or error message
- `failures[].path` -- source file path
- `failures[].line_number` -- exact line of failure
- `failures[].issue_type` -- type of issue
- `repetitions` -- if present, shows retry behavior (flaky detection)
- `crash_report` -- crash data if test runner crashed

## Step 6: Inspect Attachments

The `tuist test case run show` output includes attachment and crash report information. Review:
- Screenshots or UI test artifacts
- Log files or crash reports
- Any diagnostic data attached to failing runs

## Summary Format

Produce a summary with:

1. **Overall verdict**: Better, worse, or neutral compared to base.
2. **New failures**: List each with failure message, file path, and line number.
3. **New flaky tests**: List with flakiness context.
4. **Fixed tests**: List tests that are now passing.
5. **Duration**: Overall and notable per-test regressions.
6. **Recommendations**: Actionable next steps for each issue.

Example:

```
Test Run Comparison: base (run-123 on main) vs head (run-456 on feature-x)

Status: success -> failure -- REGRESSION
Duration: 120.5s -> 145.2s (+21%)
Tests: 342 -> 345 (3 new tests)
Failures: 0 -> 2 (2 new failures)
Flaky: 1 -> 3 (2 newly flaky)

New Failures:
1. AuthModuleTests/LoginTests/test_login_with_expired_token
   Message: "Expected status 401, got 500"
   File: Tests/AuthModuleTests/LoginTests.swift:42
   Likely cause: Server error handling changed for expired tokens

2. NetworkTests/RetryTests/test_retry_on_timeout
   Message: "Timed out waiting for retry"
   File: Tests/NetworkTests/RetryTests.swift:87
   Likely cause: Timeout threshold too low after network layer refactor

Newly Flaky:
1. CacheTests/WriteCacheTests/test_concurrent_writes (flaky in 3/5 runs)

Recommendations:
- Fix expired token handling in AuthModule
- Increase timeout in RetryTests or mock the network layer
- Investigate concurrent write synchronization in CacheTests
```

## Done Checklist

- Resolved both base and head test runs
- Compared top-level metrics
- Identified new failures, fixed tests, and flaky changes
- Inspected failure details for new failures
- Provided actionable recommendations with file paths
