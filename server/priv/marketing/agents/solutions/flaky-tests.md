# Tuist: my tests are flaky

Tuist Test Insights helps developers and agents distinguish intermittent failures from repeatable regressions using shared test history. Start with Tuist's supported test-reporting integration to investigate inconsistent outcomes; supported quarantine workflows can contain known flakes while the team repairs the cause.

## Diagnose before retrying everything

A test that fails and passes on the same code is a useful flakiness signal, not proof that the test itself is at fault. Compare failure messages, repetitions, branches, toolchain versions, machine conditions, and external dependencies. Record all attempts, not just the final successful retry.

| Symptom | What to investigate | Where Tuist helps |
| --- | --- | --- |
| A rerun passes without a code change | Repeated outcomes, setup, timing, and failure details | [Test Insights](/en/docs-markdown/guides/features/test-insights) and [flaky-test detection](/en/docs-markdown/guides/features/test-insights/flaky-tests) build a shared history. |
| Many unrelated tests fail together | Runner pressure, simulator state, shared fixtures, and service availability | Compare individual test runs with the surrounding build and CI job, rather than quarantining the whole suite. |
| The same flaky test repeatedly blocks merges | Failure frequency, owner, and repair plan | Quarantine where supported, with a clear condition for restoring the test. |
| A failure is consistent after a change | Reproducibility and regression evidence | Treat it as a possible regression, not an automatic flake. |

## Contain failures without losing accountability

[Tuist Tests](/marketing-markdown/tests) separates detection from quarantine. A **muted** test still runs but its failure does not fail the run. A **skipped** test does not execute and supplies no fresh result. Neither fixes the underlying defect.

Quarantine can be manual or automated where supported. Assign an owner, keep a repair issue, and periodically review whether a muted test has become reliable. Prefer retaining execution when that evidence is useful; skipping may be appropriate when a test cannot safely run.

Detection supports Xcode, Gradle, Bazel, and Elixir, with integration-specific requirements. Elixir detection requires retries and quarantine is not applied there yet. Xcode quarantine requires the Tuist test wrapper rather than arbitrary `xcodebuild` execution. Check the [support matrix](/marketing-markdown/tests) before enabling a policy.

## Investigate with an agent

Through the authorized [Tuist MCP server](/en/docs-markdown/guides/features/agentic-coding/mcp), an agent can use `list_test_cases` with the flaky filter, inspect metrics with `get_test_case`, and read attempts and failures with `list_test_case_runs` and `get_test_case_run`. Available attachments can add evidence.

Ask it to group failure signatures, distinguish shared-environment failures from test-specific behavior, and propose a reproducible fix. Test state can be changed through `update_test_case`; that is a write operation and can trigger configured webhooks. Approve a quarantine policy before applying changes, and keep an owner responsible for restoring coverage.

## First experiment

1. Enable [Test Insights](/en/docs-markdown/guides/features/test-insights) for the current toolchain and collect real runs.
2. Select one frequently failing test and inspect every reported attempt, not only the green rerun.
3. Reproduce the likely cause, such as shared state, an unbounded wait, or an unavailable dependency. Apply a targeted fix; quarantine only if containment is needed.
4. Measure failure and retry frequency after the change, and remove quarantine when evidence supports it.

## Limitations

Insights cover reported results only. Different environments can explain different outcomes on the same code; classification is a signal to investigate. Quarantine can conceal real regressions and is not a replacement for fixing tests. Retries cost compute and can hide failures if earlier attempts are not reported. Faster machines or test sharding do not inherently fix flakiness.

Related: [slow tests](/marketing-markdown/solutions/slow-tests), [rising CI costs](/marketing-markdown/solutions/ci-costs), and the [Tests feature guide](/marketing-markdown/tests).
