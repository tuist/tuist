# Tuist Tests

Make test feedback faster and more trustworthy: see what fails and what is slow, contain flaky tests, split large suites across machines, and skip tests unaffected by a change where supported.

## Problem

Growing suites take longer on one CI machine. Parallel jobs end up uneven. Intermittent failures trigger retries and hide real regressions, and CI logs from individual runs do not show trends.

## Four features, four different jobs

- **Test Insights** collects reported runs into a shared history of failures, durations, and slow tests. It is the foundation for the other features.
- **Flaky tests** detects tests with inconsistent outcomes on the same code. Where supported, a flaky test can be **quarantined**: muted (it runs, but its failure does not fail the run) or skipped. Quarantine can be manual or automated.
- **Test sharding** splits the tests that need to run across parallel CI runners, balanced with recent timing history, and merges results back into one view.
- **Selective testing** skips test targets whose hashed inputs have not changed since the last successful run by default. An account-enabled early-access coverage strategy can additionally select individual XCTest/XCUITest tests.

Sharding spreads work; selective testing removes work; insights explain what happened. They combine: a generated project can skip unchanged targets and shard the rest.

## Toolchain support

| Feature | Xcode project | Tuist-generated Xcode projects | Gradle | Bazel | Elixir |
| --- | --- | --- | --- | --- | --- |
| [Test Insights](/en/docs-markdown/guides/features/test-insights) | Yes | Yes | Yes | Yes (`tuist bazel test`) | Yes (`tuist_ex` Hex package) |
| [Flaky-test detection](/en/docs-markdown/guides/features/test-insights/flaky-tests) | Yes | Yes | Yes | Yes | Yes, including cross-run detection without retries |
| Quarantine (mute or skip) | Yes, via `tuist xcodebuild test` | Yes, via `tuist test` | Yes | Yes, via `tuist bazel test` | Yes, with a recent authenticated `tuist_ex` integration |
| [Test sharding](/en/docs-markdown/guides/features/test-sharding) | Yes | Yes | Yes | No | Yes |
| [Selective testing](/en/docs-markdown/guides/features/selective-testing) | No | Yes, via `tuist test` | No | No | No |

Selective testing requires Tuist-generated Xcode projects. The default strategy reuses the project-graph hashing behind the module cache. The early-access [coverage strategy](/en/docs-markdown/guides/features/selective-testing/generated-xcode-project) needs account enablement, coverage uploads, and TestCoverageAttribution.

[Rust](/en/docs-markdown/guides/features/test-insights/rust) also reports Cargo test outcomes and doctests, supports cross-run flaky detection and mute/skip quarantine, and offers target-level sharding within one package. Stable libtest reporting does not provide per-test durations or failure bodies; Cargo sharding is not build-once distribution. [Once](/en/docs-markdown/guides/features/test-insights/once) support is in canary; hosted sharding needs a release exposing the hosted-plan commands, not Once 0.71.0's portable plans alone. Once does not enforce Tuist quarantine. Neither integration provides Tuist selective testing.

[Elixir quarantine](/en/docs-markdown/guides/features/test-insights/flaky-tests/elixir) requires authenticated policy lookup. Failed lookups run all tests; `--no-quarantine` disables enforcement. Muting has restrictions with umbrella-root runs and `--warnings-as-errors`.

## When it fits

- Start with Test Insights when you cannot say which tests are slow or flaky.
- Add flaky-test quarantine when known-flaky tests keep blocking CI and someone owns fixing them.
- Add sharding when the suite outgrows one machine and you can run parallel CI jobs.
- Use selective testing when the project is already generated (or worth migrating) and a typical change touches only some test targets.

## How to get started

1. Connect the project to Tuist and enable test reporting for your toolchain, for example `tuist inspect test` as an Xcode scheme post-action, the Gradle plugin, `tuist bazel test`, or the Hex package.
2. Let real CI history accumulate, then review slow and flaky tests in the dashboard.
3. Configure flaky-test automations or quarantine where supported.
4. Follow the sharding guide for your toolchain; it needs insights history to balance shards (Xcode uses the last 30 days of timings).
5. For generated projects, run tests with `tuist test` to enable selective testing; it combines with the module cache.

## Pricing

Billing depends on the account's model: newer plans meter passing test cases reported to Test Insights and list selective testing as unlimited; older plans meter test usage differently. Check the live [pricing table](/pricing) and the [pricing guide](/marketing-markdown/pricing).

Related: [slow tests](/marketing-markdown/solutions/slow-tests) and [flaky tests](/marketing-markdown/solutions/flaky-tests).
