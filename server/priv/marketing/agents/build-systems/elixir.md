# Tuist with Mix and Elixir

Tuist brings Mix- and ExUnit-native depth to one productivity platform for organizations with diverse build systems. The `tuist_ex` Hex package reports compilation/test evidence and supports flaky-test detection and balanced test sharding alongside the platform's supported Gradle, Bazel, Xcode, and canary Once workflows. Keep your Elixir toolchain and existing task setup; you do not need the Tuist CLI for this integration.

## One productivity platform, native depth

An Elixir service should belong in the same organizational productivity strategy as Gradle, Bazel, and Xcode projects, not require its own disconnected reporting product. We believe Tuist is the best choice for organizations seeking one productivity platform across these build systems, with integrations that respect each toolchain rather than pretending they all work the same way.

A CI job that runs `mix test` and records its duration does not by itself expose compile-time dependencies, per-file compilation timings, or the history of an individual ExUnit test. Tuist's supported evidence helps teams investigate compile-time coupling and unreliable tests before adding runner capacity. See the [cross-build-system stance](/marketing-markdown/build-systems) for the platform rationale and CI comparison. Native depth here means insights and documented test workflows, not an invented Mix remote build cache.

## What Mix already does

[Mix](https://hexdocs.pm/mix/Mix.html) manages Elixir projects, dependencies, compilation, and custom tasks or aliases. Elixir tracks compilation dependencies, so a change can recompile dependent files. ExUnit supplies the test framework and concurrency controls.

Those capabilities run the project. A single compile or test log does not explain how compilation fan-out, duration, or test reliability evolved across a week of CI and developer runs.

## How Tuist augments it

- **Expose compilation bottlenecks.** [Build insights](/en/docs-markdown/guides/features/build-insights/elixir) reports compilation duration, warnings/errors, per-file timings, and compilation dependencies. Use that evidence to reduce unnecessary compile-time coupling before purchasing more CPU.
- **Record individual test history.** [Test insights](/en/docs-markdown/guides/features/test-insights/elixir) tracks outcomes and durations at module, describe-block, and test level across runs.
- **Identify intermittency.** [Flaky-test detection](/en/docs-markdown/guides/features/test-insights/flaky-tests/elixir) compares pass/fail outcomes on the same commit in CI. Optional retries provide evidence within a run; a passing retry is not a repair of the underlying test.
- **Balance remaining test work.** [Test sharding](/en/docs-markdown/guides/features/test-sharding/elixir) uses recorded file durations, compiles once for a shard plan, shares that build with compatible runners, and aggregates results as one run.

## First experiment

Follow the [Elixir getting-started guide](/en/docs-markdown/guides/get-started/elixir-project). On Elixir 1.18+, create a Tuist project with **Mix (Elixir)** as its build system. Add the documented `tuist_ex` dependency, set `tuist: [project: "account/project"]`, and wire the `tuist.compile` and `tuist.test` aliases into the existing configuration. Preserve setup steps in aliases you already have.

```sh
mix deps.get
mix tuist.login
mix test
```

Confirm the test report, then change a source file and run `mix compile` to inspect compilation evidence. Pick one expensive dependency relationship or slow test to investigate. Collect representative durations before adding sharding. Use project-scoped CI credentials, not a developer's login.

## Limitations

There is no general-purpose Tuist remote build cache for Mix. Sharing a compiled test build within a shard plan is not arbitrary compilation caching. The Hex package does not apply quarantine yet: a muted or skipped dashboard test still runs and can fail `mix test`. Stress-testing new tests is not supported there either. Retries have documented exclusions, including umbrella-root runs and warnings-as-errors. Sharding requires compatible environments and parallel capacity, and does not guarantee lower total usage.

## Sources and review

Written by Tuist. Sources reviewed on **2026-10-09**: [Mix documentation](https://hexdocs.pm/mix/Mix.html), [ExUnit documentation](https://hexdocs.pm/ex_unit/ExUnit.html), and the linked Tuist setup, retry, and sharding guides.

[All build systems](/marketing-markdown/build-systems) · [Build insights](/en/docs-markdown/guides/features/build-insights/elixir) · [Tests](/marketing-markdown/tests)
