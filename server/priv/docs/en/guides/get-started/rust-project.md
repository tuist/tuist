---
{
  "title": "Rust project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Connect your Rust project to Tuist to track builds and tests, find flaky tests, and split test runs across CI workers."
}
---
# Rust project {#rust-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/rust-project
```

:::

## Prerequisites

- A Rust project built with Cargo.
- The Tuist CLI and a Tuist account.
- Optionally, [cargo-nextest](https://nexte.st/docs/installation/) for per-test timing, retry history, and splitting tests across CI workers.

Tuist works with your existing Cargo project. You don't need to add a Rust dependency or change how your project builds.

> [!NOTE] Why nextest?
> Plain `cargo test` reports individual test results, including doctests. Nextest adds measured per-test durations, retry history, and build-once test sharding across CI workers. It is optional for test insights and not needed for build insights.

## Connect the project

Install the <.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link> and Rust. Create a project in the dashboard with **Cargo (Rust)** as its build system. Add a `tuist.toml` at your repository root:

```toml
project = "account/project"
# url = "https://your-tuist-server.example.com"
```

Log in with `tuist auth login`, then run your usual Cargo commands through Tuist. In CI, set `TUIST_TOKEN` to a project token. You can also set `TUIST_PROJECT` instead of adding a configuration file, and `TUIST_URL` if you use a self-hosted server.

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo test --workspace
```

Use the same arguments you normally pass to Cargo, including features, toolchains, and test filters. Cargo keeps its usual output and exit code, even if Tuist can't upload a report.

## Keep typing Cargo

With [mise's command wrappers](https://mise.jdx.dev/dev-tools/shims.html#command-wrappers) enabled, add this to `mise.toml`:

```toml
[wrappers.cargo]
command = "tuist"
args = ["cargo"]
```

Run `mise reshim` after adding the wrapper. You can then use `cargo build`, `cargo check`, `cargo test`, and `cargo nextest run` as usual. Mise runs them through Tuist for you.

> [!TIP] Coding agents
> This is useful when working with coding agents: they can keep running `cargo build` and `cargo test` without being reminded to add the `tuist` prefix.

## Build insights

Open **Builds** in the dashboard to see how long your builds take and compare local builds with CI. Select a build to find the crates that took longest to compile and inspect its warnings and errors.

The compiler timings are for crates, not individual source files. See <.localized_link href="/guides/features/build-insights/rust">Rust Build Insights</.localized_link> for more on reading a build report.

## Test insights

Run your tests as usual:

```sh
tuist cargo test --workspace
```

Open **Tests** in the dashboard to see passed, failed, and ignored tests, including doctests. Plain Cargo reports suite durations, but stable libtest does not expose per-test timings. For per-test timing and retry history, use `tuist cargo nextest run --workspace`; your existing nextest profiles and JUnit report settings still work.

Read more in <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link> and <.localized_link href="/guides/features/test-insights/flaky-tests/rust">Rust Flaky Tests</.localized_link>.

Nextest doesn't run doctests, so run those separately when using it:

```sh
tuist cargo test --doc
```

## Test sharding

Test sharding splits your test suite across CI workers that run at the same time, so you get results sooner. Tuist uses timing data from previous runs to balance the work dynamically, rather than asking you to maintain fixed groups of tests. Each shard gets a set of test binaries to run.

Build the tests once before starting the workers:

```sh
TUIST_SHARD_REFERENCE="${CI_PIPELINE_ID}-${CI_JOB_ATTEMPT}" \
  tuist cargo test-build --workspace --shard-total 4
```

Use your CI provider's pipeline and attempt identifiers for the reference. The command uploads the compiled tests and returns a plan ID and worker indexes.

Pass that plan ID to each worker, with a different index starting at zero:

```sh
TUIST_SHARD_PLAN_ID="$PLAN_ID" TUIST_SHARD_INDEX=0 \
  tuist cargo nextest run --profile ci
```

Each worker downloads the compiled tests and runs its assigned binaries without rebuilding. Use the same checkout and compatible operating systems and architectures on all workers. The results appear as one test run in the dashboard.

See <.localized_link href="/guides/features/test-sharding/rust">Rust Test Sharding</.localized_link> for a complete CI example and options for balancing the workers.
