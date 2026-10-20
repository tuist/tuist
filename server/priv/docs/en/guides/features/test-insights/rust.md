---
{
  "title": "Rust Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track Cargo test results, including Rust doctests, in the Tuist dashboard."
}
---
# Rust test insights {#rust-test-insights}

Tuist reports individual test results from `cargo test`, including unit tests, integration tests, and doctests. No Rust dependency or additional test runner is required.

> [!IMPORTANT] Requirements
> - Follow the <.localized_link href="/guides/get-started/rust-project">Rust project setup</.localized_link>.

## Report your test runs {#report-your-test-runs}

```sh
tuist cargo test --workspace
```

With the mise Cargo wrapper configured, you can keep typing `cargo test`. Cargo still compiles and runs your tests, with its usual arguments, output, and exit code. Reporting failures do not change the result of your tests.

You can select a package or filter tests as usual:

```sh
tuist cargo test -p store
tuist cargo test authentication
```

## What Tuist tracks {#what-is-tracked}

- Passed, failed, and ignored tests from completed test suites.
- Unit tests, integration tests, and doctests.
- Whole-suite durations.
- Available branch, commit, CI, and runner metadata.

Filtered tests and tests not executed after a failure are never reported as passing. Results appear under **Tests** in the dashboard.

## Packages, modules, and test cases {#test-hierarchy}

Tuist groups results by Cargo package and target. Rust module paths group individual tests within a target:

| Dashboard label | Rust meaning | Example |
| --- | --- | --- |
| Modules | Cargo package and target | `store::api` |
| Test Suites | Rust module paths | `api::authentication` |
| Test Cases | Individual tests | `rejects_invalid_token` |

Doctests use a separate module such as `store::doctest/store`. Their names include the source location, so moving an example can change its identity.

## Doctests and durations {#cargo-test}

Doctests run with your usual test command, including `compile_fail`, `should_panic`, and `no_run` examples. To run only doctests:

```sh
tuist cargo test --doc
```

Stable libtest reports whole-suite time but not individual test durations. Unavailable timings are excluded from per-case duration histories and duration analytics, while test outcomes still contribute to reliability and run counts.

## Reporting limits {#reporting-limits}

Individual results are collected from Cargo/libtest's default output. Commands using `--no-run`, `--list`, quiet or Cargo-verbose output, alternate formats, or uncaptured test output run normally without individual test reporting. Custom harnesses, incomplete summaries, ambiguous target attribution, and oversized reports are not uploaded.

If workspace packages have identically named integration targets, select one with `-p <package>`. Reporting supports exact workspace package names; dependency packages, version-qualified selectors, and globs execute normally but are not reported. Absolute doctest paths are omitted to keep checkout paths out of test identities.

Tuist streams output while collecting results. This can affect automatic color detection. Background processes that keep output pipes open after Cargo exits can cause the report to be omitted, but do not change Cargo's exit status.

## Reliability and selection {#reliability-and-selection}

Use <.localized_link href="/guides/features/test-insights/flaky-tests/rust">flaky test detection</.localized_link> to investigate unstable tests. Dashboard quarantine does not currently mute or skip Cargo tests. Coverage ingestion, coverage-based test selection, and build-once sharding are not available for plain Cargo test runs.

## Troubleshooting {#troubleshooting}

If a test run doesn't appear in the dashboard, enable debug output to see why its report wasn't sent:

```sh
TUIST_DEBUG=1 tuist cargo test --workspace
```
