---
{
  "title": "Once Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Inspect Once test suites, individual results, failures, and durations in the Tuist dashboard."
}
---
# Once test insights {#once-test-insights}

Once reports test results to Tuist so you can follow your suite across local and CI runs, investigate failures, and find slow tests without collecting reports from individual workers.

> [!IMPORTANT]
> **Requirements**
>
> - Complete <.localized_link href="/guides/get-started/once-project">Get started with Once</.localized_link>.
> - Use test targets that report structured results. Available detail depends on the target kind and test runner.

## Report your test runs {#report-your-test-runs}

Run the whole suite or select a target:

```bash
once test
once test MyTests
```

Once streams native test events and publishes completed results into Tuist's shared test model. **Tests** and **Test Runs** show the runs; individual cases also have shared test history. A <.localized_link href="/guides/features/test-sharding/once">hosted sharded run</.localized_link> publishes one report per worker into a combined run instead of counting its diagnostic event stream again.

## What is tracked {#what-is-tracked}

- Reported test targets, suites, and individual cases.
- Passed, failed, and skipped outcomes, with durations when supplied by the runner.
- Failure messages supplied by the runner in hosted sharded reports.
- Ordered retry attempts and flaky results when a test fails and later passes.
- Branch, commit, and CI context supplied by Once.

Test identity uses the native target, suite, and case name. Sharding batch IDs are scheduling units, not test names.

Ordinary `once test` reporting preserves outcomes and retry attempts but does not currently include failure messages in shared test history. Hosted sharded reports can include failure messages, but neither reporting path supplies source locations. Keep your CI logs for diagnostics that are not available in Tuist.

Not every test target provides the same detail. Some runners report individual cases, others only summaries; exact file or case execution is a separate capability. See [Once's test ecosystem coverage](https://buildonce.dev/docs/guide/graph/testing#understand-current-ecosystem-coverage) before relying on per-case analytics or fine-grained scheduling.

## Flaky tests {#flaky-tests}

Tuist uses reported attempts and CI history to identify inconsistent results. Reporting an attempt is not the same as enabling retries: configure retries in the runner that supports them. See <.localized_link href="/guides/features/test-insights/flaky-tests/once">Once flaky tests</.localized_link> for detection and the current quarantine boundary.

## Selection and code coverage {#selection-and-code-coverage}

Once can select tests conservatively from its local graph with `--changed-path`. That is Once's own selection, not Tuist's hosted coverage-based test selection:

```bash
once test --changed-path src/library.rs
```

Native Once reporting does not currently upload code coverage to Tuist. A successful test report or shard plan does not populate the Code Coverage dashboard.

## Troubleshooting {#troubleshooting}

If a run is missing, check that the effective cache provider names your Tuist project and authenticate again with `once auth login --provider tuist`. Live reporting is best-effort and does not turn an otherwise successful test command into a failure when the reporting service is unavailable.

Run summaries and structured test failures are not full process logs. This server does not currently ingest Once's raw action log stream; keep your CI logs for output that is not included in structured results.
