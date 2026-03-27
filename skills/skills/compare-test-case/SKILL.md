---
name: compare-test-case
description: Compares a single test case's behavior across two branches, analyzing pass/fail status, duration, flakiness, and failure details. Useful for investigating test regressions introduced by a feature branch.
---

# Compare Test Case

## Quick Start

You'll typically receive a test case identifier and two branches. Follow these steps:

1. Run `tuist test case show <id-or-identifier> --json` to get the test case metrics.
2. Run `tuist test case run list <identifier> --json` to see runs across branches.
3. Compare behavior between base and head branches.
4. Inspect failures with `tuist test case run show <run-id> --json`.
5. Summarize findings with root cause analysis.

## Step 1: Resolve the Test Case

### By ID or dashboard URL

```bash
tuist test case show <test-case-id> --json
```

### By identifier (Module/Suite/TestCase)

```bash
tuist test case show Module/Suite/TestCase --json
```

### If no test case is provided

Discover flaky or failing tests to investigate:

```bash
tuist test case list --flaky --json --page-size 10
```

Key fields from the response:
- `id` -- unique identifier for subsequent commands
- `name`, `module_name`, `suite_name` -- the test identity
- `reliability_rate` -- percentage of successful runs
- `flakiness_rate` -- percentage of flaky runs in the last 30 days
- `total_runs` / `failed_runs` -- volume context
- `is_flaky` / `is_quarantined` -- current flags

## Step 2: Get Runs on Each Branch

List test case runs filtered by the test case, and look at the `git_branch` field:

```bash
tuist test case run list <identifier> --json --page-size 20
```

Separate runs by branch. For each branch, compute:
- Pass rate: `passed_runs / total_runs * 100`
- Average duration
- Flaky run count
- Most recent status

### Defaults

- If no base branch is provided, use the project's default branch (usually `main`).
- If no head branch is provided, detect the current git branch.

## Step 3: Compare Branch Behavior

| Metric | Base branch | Head branch | Verdict |
|---|---|---|---|
| Pass rate | e.g. 100% | e.g. 60% | REGRESSION |
| Avg duration | e.g. 0.5s | e.g. 2.1s | REGRESSION |
| Flaky runs | 0 | 3 | NEW FLAKINESS |
| Last status | success | failure | REGRESSION |

Classify the change:
- **Newly failing**: 100% pass rate on base, <100% on head
- **Newly flaky**: No flaky runs on base, flaky runs on head
- **Duration regression**: >50% increase in average duration
- **Fixed**: Failing on base, passing on head
- **Stable**: Same behavior on both branches

## Step 4: Inspect Failures

For each failing run on the head branch:

```bash
tuist test case run show <test-case-run-id> --json
```

Examine:
- `failures[].message` -- the assertion or error message
- `failures[].path` -- source file path
- `failures[].line_number` -- exact line of failure
- `failures[].issue_type` -- type of issue
- `repetitions` -- shows retry behavior (e.g., pass-fail-pass means flaky)
- `crash_report` -- crash data if the test runner crashed

## Step 5: Identify Root Cause

Based on the comparison:

### Newly failing
- Check commits between base and head branches for changes to the test file or the code under test.
- Look at the failure message for clues about what changed.

### Newly flaky
- Common patterns: timing/async issues, shared state, environment dependencies.
- Check if `repetitions` show intermittent pass/fail patterns.
- See the fix-flaky-tests skill for detailed flaky test analysis patterns.

### Duration regression
- Check if setup/teardown time increased.
- Check if the test is doing more work (new assertions, larger data sets).
- Check if a dependency became slower.

## Summary Format

Produce a summary with:

1. **Test case info**: Name, module, suite, overall reliability.
2. **Base branch behavior**: Pass rate, avg duration, flaky count.
3. **Head branch behavior**: Pass rate, avg duration, flaky count.
4. **Verdict**: What changed and classification.
5. **Root cause**: Hypothesis based on failure analysis.
6. **Recommendations**: Specific file paths, line numbers, and fix suggestions.

Example:

```
Test Case Comparison: AuthModuleTests/LoginTests/test_login_with_expired_token

Overall reliability: 85% (was 100% before head branch)

Base (main):
  Pass rate: 100% (15/15 runs)
  Avg duration: 0.3s
  Flaky: No

Head (feature/auth-refactor):
  Pass rate: 60% (3/5 runs)
  Avg duration: 0.5s
  Flaky: Yes (2 flaky runs)

Verdict: NEWLY FLAKY -- test was stable on main but intermittently fails on feature branch

Root cause: The auth refactor introduced an async token refresh that races with the
test's synchronous assertion. Failures show "Expected status 401, got nil" at
Tests/AuthModuleTests/LoginTests.swift:42, suggesting the response arrives before
the token refresh completes.

Recommendations:
- Add an await/expectation before the assertion at LoginTests.swift:42
- Consider mocking the token refresh to make the test deterministic
```

## Done Checklist

- Resolved the test case identity
- Gathered runs on both branches
- Compared pass rates, durations, and flakiness
- Inspected failure details for failing runs
- Identified root cause with file paths and line numbers
- Provided actionable fix recommendations
