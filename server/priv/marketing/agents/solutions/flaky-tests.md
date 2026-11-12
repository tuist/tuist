# Tuist: my tests are flaky

Tuist Test Insights helps developers and agents distinguish intermittent failures from repeatable regressions using shared test history. Start with Tuist's supported test-reporting integration to investigate inconsistent outcomes; supported quarantine workflows can contain known flakes while the team repairs the cause.

## Why flaky tests are expensive

A flaky test passes and fails on the same code. Each failure costs more than a rerun:

- **Blocked merges.** A red check stops a pull request until someone retries it, and in a merge queue it can hold up everyone behind it.
- **Wasted investigation.** Someone has to decide whether the failure is real. Without history, that means reading logs from scratch every time.
- **Eroded trust.** Once a team learns that red often means nothing, real regressions get retried and merged too.
- **Hidden cost.** Blanket retries turn a flaky test green, so the cost moves into longer jobs and extra machine time instead of disappearing.

Common causes are shared state between tests, timing assumptions and fixed waits, test order dependence, unavailable external services, and resource pressure on the machine. Tuist does not guess which one applies. It records every attempt, so the evidence points to the cause.

## How Tuist addresses it

- **Detection from history.** Tuist marks a test as flaky when it fails and passes on the same code, both within a run's retries and, for supported integrations, across separate CI runs. See [flaky-test detection](/en/docs-markdown/guides/features/test-insights/flaky-tests).
- **Containment.** Quarantine mutes or skips a known flaky test, manually or through an automation threshold, so it stops blocking merges while it is fixed. Every change is recorded.
- **Shared evidence.** Developers, reviewers, and authorized coding agents see the same attempts and failure messages, and teams can get [Slack alerts](/en/docs-markdown/guides/integrations/slack) when a test becomes flaky.

## Diagnose before retrying everything

A test that fails and passes on the same code is a useful flakiness signal, not proof that the test itself is at fault. Compare failure messages, repetitions, branches, toolchain versions, machine conditions, and external dependencies. Record all attempts, not just the final successful retry.

| Symptom | What to investigate | Where Tuist helps |
| --- | --- | --- |
| A rerun passes without a code change | Repeated outcomes, setup, timing, and failure details | [Test Insights](/en/docs-markdown/guides/features/test-insights) and [flaky-test detection](/en/docs-markdown/guides/features/test-insights/flaky-tests) build a shared history. |
| Many unrelated tests fail together | Runner pressure, simulator state, shared fixtures, and service availability | Compare individual test runs with the surrounding build and CI job, rather than quarantining the whole suite. |
| The same flaky test repeatedly blocks merges | Failure frequency, owner, and repair plan | Quarantine where supported, with a clear condition for restoring the test. |
| A failure is consistent after a change | Reproducibility and regression evidence | Treat it as a possible regression, not an automatic flake. |

## Project first, environment second

Use the project's failure history to repair shared state, timing assumptions, and unreliable dependencies before scaling its execution environment. Check runner conditions when evidence points there, but do not treat a faster machine as a fix for an unexplained flake. Supported Gradle, Bazel, Elixir, and Xcode reporting can ground that investigation without moving CI.

## Contain failures without losing accountability

[Tuist Tests](/marketing-markdown/tests) separates detection from quarantine. A **muted** test still runs but its failure does not fail the run. A **skipped** test does not execute and supplies no fresh result. Neither fixes the underlying defect.

Quarantine can be manual or automated where supported. Assign an owner, keep a repair issue, and periodically review whether a muted test has become reliable. Prefer retaining execution when that evidence is useful; skipping may be appropriate when a test cannot safely run.

Detection supports Xcode, Gradle, Bazel, and Elixir, with integration-specific requirements. Elixir supports cross-run detection without retries and mute/skip quarantine with recent authenticated `tuist_ex` versions. Muting has restrictions with umbrella-root runs and `--warnings-as-errors`; failed policy lookups run all tests. Xcode quarantine requires the Tuist test wrapper rather than arbitrary `xcodebuild` execution. Check the [support matrix](/marketing-markdown/tests), including Cargo and canary Once support, before enabling a policy.

## Investigate with an agent

Through the authorized [Tuist MCP server](/en/docs-markdown/guides/features/agentic-coding/mcp), an agent can use `list_test_cases` with the flaky filter, inspect metrics with `get_test_case`, and read attempts and failures with `list_test_case_runs` and `get_test_case_run`. Available attachments can add evidence.

Ask it to group failure signatures, distinguish shared-environment failures from test-specific behavior, and propose a reproducible fix. Test state can be changed through `update_test_case`; that is a write operation and can trigger configured webhooks. Approve a quarantine policy before applying changes, and keep an owner responsible for restoring coverage.

## First experiment

1. Enable [Test Insights](/en/docs-markdown/guides/features/test-insights) for the current toolchain and collect real runs.
2. Select one frequently failing test and inspect every reported attempt, not only the green rerun.
3. Reproduce the likely cause, such as shared state, an unbounded wait, or an unavailable dependency. Apply a targeted fix; quarantine only if containment is needed.
4. Measure failure and retry frequency after the change, and remove quarantine when evidence supports it.

## Further reading

- [Stop flaky tests from blocking your PRs](/blog/2026/01/27/flaky-tests) on detection, tracking, and quarantine.
- [Tuist now supports detecting flaky tests](/blog/2024/07/10/detecting-flaky-tests) on how detection started.
- Related guides: [slow tests](/marketing-markdown/solutions/slow-tests), [rising CI costs](/marketing-markdown/solutions/ci-costs), and the [Tests feature guide](/marketing-markdown/tests).

## Frequently asked questions

### How does Tuist decide that a test is flaky?

A test is flaky when it both fails and passes on the same code. Tuist sees this when a retry within a run passes after a failure and, for supported integrations, when matching CI runs on the same commit disagree. Runs on different schemes, devices, or OS versions do not flag each other.

### What is the difference between muting and skipping a test?

A muted test still runs and reports its result, but its failure does not fail the run. A skipped test does not run at all, so it produces no new evidence. Muting is usually the better default because the history keeps growing.

### Does quarantining fix a flaky test?

No. Quarantine stops a known flaky test from blocking merges while someone fixes it. Assign an owner, keep a repair issue, and release the test once it is reliable again.

### Should we just retry failed tests?

Retries hide the symptom and add machine time. They are useful as a detection signal, because a retry that passes marks the test as flaky, but they are not a fix. Use the recorded attempts to find and remove the cause.

### Can a coding agent investigate flaky tests?

Yes. Through the Tuist MCP server, an authorized agent can list flaky tests, read their attempts and failure messages, and propose a fix. Changing a test's quarantine state is a write operation that should follow your team's approval process.
