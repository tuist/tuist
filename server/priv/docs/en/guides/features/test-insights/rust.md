---
{
  "title": "Rust Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track Cargo and nextest test results, including Rust doctests, in the Tuist dashboard."
}
---
# Rust test insights {#rust-test-insights}

Tuist reports individual test results from plain `cargo test`, including doctests. You can also use `cargo nextest run` for measured per-test durations, retry history, and test sharding. No Rust dependency or additional test runner is required for plain Cargo reporting.

> [!IMPORTANT] Requirements
> - Follow the <.localized_link href="/guides/get-started/rust-project">Rust project setup</.localized_link>.
> - Install [cargo-nextest](https://nexte.st/docs/installation/) only if you want to use nextest.

## Report your test runs {#report-your-test-runs}

```sh
tuist cargo test --workspace
```

With the mise Cargo wrapper configured, you can keep typing `cargo test`. Cargo still compiles and runs your tests; Tuist does not replace it with nextest. See [Plain Cargo tests and doctests](#cargo-test) for reporting details.

For nextest:

```sh
tuist cargo nextest run --workspace
```

Keep using your normal nextest arguments, features, filtersets, and profiles:

```sh
tuist cargo nextest run --profile ci -E 'test(authentication)'
```

Tuist adds its JUnit configuration through a nextest tool configuration. Your selected profile and any existing JUnit destination are respected. Existing reports are not deleted; Tuist only uploads a report if it can verify that the invocation wrote a fresh one. Reporting does not alter nextest's exit status.

## What nextest tracks {#what-is-tracked}

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

`tuist cargo test` reports passed, failed, and ignored tests from Cargo/libtest's default output on stable Rust. This includes unit tests, integration tests, and doctests, including `compile_fail`, `should_panic`, and `no_run` examples. To run only doctests:

```sh
tuist cargo test --doc
```

Results appear under **Tests** as `cargo test`. Module identities come from Cargo package and target metadata, not executable hashes. Doctests use a separate `<package>::doctest/<library>` module; their names include the source location, so moving an example can change its identity.

Stable libtest output reports whole-suite time but not individual test durations. Tuist sends zero for unavailable test-case and Rust-namespace timings; these are not measured zero-duration tests and are excluded from per-case duration histories and aggregate timing analytics. Outcomes still contribute to reliability and run counts. The `cargo test` and `cargo test · <label>` scheme values are reserved for unmeasured reporting across all build systems. Nextest automatically prefixes custom labels that would collide with these values with `cargo nextest run · `, preserving their measured durations; other report producers must not use the reserved schemes for measured tests. Use nextest when you need per-test timing, retries, discovery, or sharding. Nextest does not execute doctests, so run `cargo test --doc` separately when using it.

Tuist streams stdout and stderr while collecting up to 50 MB for parsing. This uses pipes, which can affect automatic color detection. Nonexecuting commands (`--no-run`, `--list`), quiet or Cargo-verbose output (`-v`, `-vv`, `--verbose`, `CARGO_TERM_VERBOSE`, or `CARGO_TERM_QUIET`), alternate output formats, and uncaptured test output are forwarded without individual test reporting. Custom harnesses, incomplete summaries, ambiguous target attribution, and reports exceeding the limits are not uploaded. In workspaces where packages have identically named integration targets, select a package explicitly with `-p <package>`; otherwise Cargo's output may not identify which package ran a target. Reporting supports exact workspace package names with `-p` or `--package`; dependency packages, version-qualified selectors, and globs still execute normally but are not reported. Reports containing absolute doctest paths are omitted to keep checkout paths out of test identities. Tuist never treats filtered or unexecuted tests as passed. After Cargo exits, Tuist drains buffered output and waits for 250 ms of inactivity rather than waiting indefinitely for background descendants that inherited its pipes. Waiting for additional output is capped at two seconds after exit, even when a descendant periodically writes more data. Time blocked writing to a slow output consumer counts toward neither limit. Already-buffered bytes are drained first, and continuously writing descendants have an 8 MB post-exit allowance per output stream. If reading stops before EOF, the test report is omitted.

## Reliability and selection {#reliability-and-selection}

Use <.localized_link href="/guides/features/test-insights/flaky-tests/rust">flaky test detection</.localized_link> to investigate unstable tests. Dashboard quarantine state does not currently mute or skip nextest execution. Coverage ingestion and coverage-based test selection are not enabled for Cargo.

## Troubleshooting {#troubleshooting}

If a test run doesn't appear in the dashboard, enable debug output to see why its report wasn't sent:

```sh
TUIST_DEBUG=1 tuist cargo nextest run --profile ci
```

Reporting doesn't change the result of your tests.
