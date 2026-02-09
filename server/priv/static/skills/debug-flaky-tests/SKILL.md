---
name: debug-flaky-tests
description: Debugs flaky tests in Tuist projects by analyzing failure patterns, identifying root causes, and applying fixes. Use when a test intermittently passes and fails, or when Tuist marks tests as flaky.
---

# Debug Flaky Tests

## Quick Start

1. Run `tuist test case list --flaky --json --page-size 50` to discover all flaky tests.
2. For each flaky test, run `tuist test case show <id> --json` to see reliability metrics.
3. Run `tuist test case run list Module/Suite/TestCase --flaky --json` to see flaky run patterns.
4. Run `tuist test case run show <run-id> --json` on failing runs to get failure messages and file paths.
5. Read the test source at the reported path and line, identify the flaky pattern, and fix it.
6. Verify with `tuist test run --scheme <scheme> --test-targets <module>/<test>`.

## Preflight Checklist

- The project is connected to Tuist (`tuist.swift` has a `fullHandle`)
- Tests have been reported (at least one `tuist test` run has completed)
- You have network access to the Tuist server

## Discovery

List all flaky test cases:

```bash
tuist test case list --flaky --json --page-size 50
```

Each result includes `id`, `name`, `module`, `suite`, `is_flaky`, and `avg_duration`. Note the `id` for investigation.

## Investigation

For each flaky test case, gather data in this order:

### 1. Get test case metrics

```bash
tuist test case show <test-case-id> --json
```

Key fields:
- `reliability_rate` — percentage of successful runs (higher is better)
- `flakiness_rate` — percentage of runs marked flaky in the last 30 days
- `total_runs` / `failed_runs` — volume context
- `last_status` — current state

### 2. View flaky run history

```bash
tuist test case run list Module/Suite/TestCase --flaky --json
```

The identifier uses the format `ModuleName/SuiteName/TestCaseName` or `ModuleName/TestCaseName` when there is no suite. This returns only runs that were detected as flaky.

### 3. View full run history

```bash
tuist test case run list Module/Suite/TestCase --json --page-size 20
```

Look for patterns:
- Does it fail on specific branches?
- Does it fail only on CI (`is_ci: true`) or also locally?
- Are failures clustered around specific commits?

### 4. Get failure details

```bash
tuist test case run show <run-id> --json
```

Key fields:
- `failures[].message` — the assertion or error message
- `failures[].path` — source file path
- `failures[].line_number` — exact line of failure
- `failures[].issue_type` — type of issue (assertion_failure, etc.)
- `repetitions` — if present, shows retry behavior (pass/fail sequence)

## Code Analysis

1. Open the file at `failures[0].path` and go to `failures[0].line_number`.
2. Read the full test function and its setup/teardown.
3. Identify which of the common flaky patterns below applies.
4. Check if the test shares state with other tests in the same suite.

## Common Flaky Patterns

### Timing and async issues
- **Missing waits**: Test checks a result before an async operation completes. Fix: use `await`, expectations with timeouts, or polling.
- **Race conditions**: Multiple concurrent operations access shared state. Fix: synchronize access or use serial queues.
- **Hardcoded timeouts**: `sleep(1)` or fixed delays that are too short on CI. Fix: use condition-based waits instead of fixed delays.

### Shared state
- **Test pollution**: One test modifies global/static state that another test depends on. Fix: reset state in setUp/tearDown or use unique instances per test.
- **Singleton contamination**: Shared singletons carry state between tests. Fix: inject dependencies or reset singletons.
- **File system leftovers**: Tests leave files that affect subsequent runs. Fix: use temporary directories and clean up.

### Environment dependencies
- **Network calls**: Tests hit real services that may be slow or unavailable. Fix: mock network calls.
- **Date/time sensitivity**: Tests depend on current time or timezone. Fix: inject a clock or freeze time.
- **File system paths**: Hardcoded paths that differ between environments. Fix: use relative paths or temp directories.

### Order dependence
- **Implicit ordering**: Test passes only when run after another test that sets up required state. Fix: make each test self-contained.
- **Parallel execution conflicts**: Tests that work in isolation but fail when run concurrently. Fix: use unique resources per test.

### Resource contention
- **Database locks**: Tests competing for the same database resources. Fix: use transactions or unique test data.
- **Port conflicts**: Tests binding to the same network port. Fix: use dynamic port allocation.
- **File locks**: Multiple tests writing to the same file. Fix: use per-test file paths.

## Fix Implementation

After identifying the pattern:

1. Apply the smallest fix that addresses the root cause.
2. Do not refactor unrelated code.
3. If the fix requires a test utility (like a mock or helper), check if one already exists before creating a new one.
4. If the test is fundamentally unreliable and cannot be fixed quickly, consider quarantining it:
   - Quarantined tests still run but their failures do not block CI.

## Verification

Run the specific test to verify the fix:

```bash
tuist test run --scheme <scheme> --test-targets <module>/<test>
```

Run it multiple times if the flakiness is intermittent:

```bash
for i in $(seq 1 5); do tuist test run --scheme <scheme> --test-targets <module>/<test>; done
```

## Done Checklist

- Identified the root cause of flakiness
- Applied a targeted fix
- Verified the test passes consistently (multiple runs)
- Did not introduce new test dependencies or shared state
- Committed the fix with a descriptive message
