---
name: fix-flaky-tests
description: Fixes flaky tests by analyzing failure patterns from Tuist test insights, identifying root causes, and applying targeted corrections. Can be invoked with a specific test case URL (e.g. `https://tuist.dev/{account}/{project}/tests/test-cases/{id}`) or without arguments to discover and fix all flaky tests in the project.
---

# Fix Flaky Tests

## Quick Start

You'll typically receive a Tuist test case URL or identifier. Follow these steps to investigate and fix it:

1. Run `tuist test case show <id-or-identifier> --json` to get reliability metrics for the test.
2. Run `tuist test case run list Module/Suite/TestCase --flaky --json` to see flaky run patterns.
3. Run `tuist test case run show <run-id> --json` on failing flaky runs to get failure messages and file paths.
4. Read the test source at the reported path and line, identify the flaky pattern, and fix it.
5. Verify by running the test multiple times to confirm it passes consistently.

If no specific test is provided, start with the Discovery section below.

## Discovery

When no specific test case is provided, find all flaky tests in the project:

```bash
tuist test case list --flaky --json --page-size 50
```

This returns all test cases currently flagged as flaky. Key fields:
- `module.name` / `suite.name` / `name` — the test identifier
- `avg_duration` — helps prioritize (fix fast unit tests first)
- `is_quarantined` — whether the test is already quarantined

**Triage strategy:**
1. Group tests by suite — multiple flaky tests in the same suite often share a root cause.
2. Check if failures share a `test_run_id` — tests that all failed in the same run may have been killed by a process crash, not individual test bugs.
3. Look at failure messages to categorize: test logic bugs vs infrastructure issues (network errors, server 502s, conflicts on retry).

## Investigation

### 1. Get test case metrics

You can pass either the UUID or the `Module/Suite/TestCase` identifier:

```bash
tuist test case show <id> --json
tuist test case show Module/Suite/TestCase --json
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
- `test_run_id` — the broader test run this execution belongs to

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


## Fix Implementation

After identifying the pattern:

1. Apply the smallest fix that addresses the root cause.
2. Do not refactor unrelated code.
3. If the fix requires a test utility (like a mock or helper), check if one already exists before creating a new one.

## Verification

### Running tests repeatedly

Run the specific test repeatedly until failure using `xcodebuild`'s built-in repetition support:

```bash
xcodebuild test -workspace <workspace> -scheme <scheme> -only-testing <module>/<suite>/<test> -test-iterations <count> -run-tests-until-failure
```

This runs the test up to `<count>` times and stops at the first failure. Choose the iteration count based on how long the test takes — for fast unit tests use 50–100, for slower integration or acceptance tests use 2–5.

### Reproducing before fixing

Before applying a fix, try to reproduce the flaky failure locally. A successful reproduction confirms your root cause analysis and lets you verify the fix directly. Use the "Running tests repeatedly" approach above, or the race condition strategies below if concurrency is suspected.

Some flaky scenarios — especially race conditions, CI-specific timing issues, or environment-dependent failures — may be difficult or impossible to reproduce locally. If you cannot reproduce after reasonable effort, proceed with fixing based on code analysis and failure logs. A fix backed by clear evidence of a bug (e.g. unsynchronized shared state, TOCTOU pattern) is valid even without local reproduction.

### Reproducing race conditions

Race conditions and concurrency bugs often only manifest under CI-level parallelism and are hard to reproduce locally. Try these strategies in order:

1. **Increase parallelism**: Add `-parallel-testing-enabled YES` to run test suites concurrently.
2. **Run broader test suites**: Instead of running a single test, run the entire module (e.g. `-only-testing ModuleTests`) to increase contention on shared resources.
3. **Thread Sanitizer**: Add `-enableThreadSanitizer YES` to detect data races deterministically. Note: TSan adds overhead which can change timing, so some races may not trigger under TSan.
4. **High iteration count with broad scope**: Combine all the above — run the full module with parallelism and many iterations.

If a race condition cannot be reproduced locally but the code is provably thread-unsafe (e.g. unsynchronized mutation of shared state), the fix is still valid. Verify the fix by confirming the tests pass with the same reproduction strategies above. Document in the commit message that the fix addresses a CI-only race condition identified through code analysis and failure logs.

## Done Checklist

- Identified the root cause of flakiness
- Applied a targeted fix
- Verified the test passes consistently (multiple runs)
- Did not introduce new test dependencies or shared state
- Committed the fix with a descriptive message
