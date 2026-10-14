---
{
  "title": "Rust Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track nextest test results, durations, failures, skipped tests, and retries in the Tuist dashboard."
}
---
# Rust test insights {#rust-test-insights}

Tuist reports the results of `cargo nextest run` using nextest's test inventory and JUnit report. No Rust dependency or separate Tuist executable is required.

> [!IMPORTANT] Requirements
> - Follow the <.localized_link href="/guides/get-started/rust-project">Rust project setup</.localized_link>.
> - Install [cargo-nextest](https://nexte.st/docs/installation/).

## Report your test runs {#report-your-test-runs}

```sh
tuist cargo nextest run --workspace
```

Keep using your normal nextest arguments, features, filtersets, and profiles:

```sh
tuist cargo nextest run --profile ci -E 'test(authentication)'
```

Tuist adds its JUnit configuration through a nextest tool configuration. Your selected profile and any existing JUnit destination are respected. Existing reports are not deleted; Tuist only uploads a report if it can verify that the invocation wrote a fresh one. Reporting does not alter nextest's exit status.

## What is tracked {#what-is-tracked}

- Per-test status and duration, including reported failures and skipped cases.
- Failure messages and retry attempts, when present in the JUnit report.
- The nextest binary ID, Rust module path, and test name.
- Available branch, commit, CI, and runner metadata.
- An inventory of discovered tests, separate from the tests actually executed.

Tests omitted after fail-fast are not reported as passing. Discovery alone is not evidence of execution. Nextest runs appear under **Tests**, not build-duration metrics.

## Binaries, modules, and test cases {#test-hierarchy}

Nextest executes **test binaries**. Each binary contains named tests such as `api::authentication::rejects_invalid_token`.

The shared dashboard currently calls these levels:

| Dashboard label | Rust meaning | Example |
| --- | --- | --- |
| Modules | Nextest test binaries | `store::test/api` |
| Test Suites | Rust module paths | `api::authentication` |
| Test Cases | Individual tests | `rejects_invalid_token` |

Binary IDs, not artifact hashes or checkout paths, identify the executable-level units. <.localized_link href="/guides/features/test-sharding/rust">Test sharding</.localized_link> assigns whole binaries, while Rust module paths group test cases for browsing.

Test-case durations describe individual work. Binary and module-path timings use reported execution windows when available, so overlapping tests are not treated as sequential work. They can include scheduling gaps and retry delays. Missing timestamps fall back to a bounded duration estimate and are not used to calibrate shard concurrency.

## Plain Cargo tests and doctests {#cargo-test}

`tuist cargo test` remains Cargo/libtest. Tuist never silently converts it into nextest, and it does not produce nextest's per-test telemetry.

Nextest does not execute doctests. Run them separately:

```sh
tuist cargo test --doc
```

## Reliability and selection {#reliability-and-selection}

Use <.localized_link href="/guides/features/test-insights/flaky-tests/rust">flaky test detection</.localized_link> to investigate unstable tests. Dashboard quarantine state does not currently mute or skip nextest execution. Coverage ingestion and coverage-based test selection are not enabled for Cargo.

## Troubleshooting {#troubleshooting}

If a test run doesn't appear in the dashboard, enable debug output to see why its report wasn't sent:

```sh
TUIST_DEBUG=1 tuist cargo nextest run --profile ci
```

Reporting doesn't change the result of your tests.
