---
{
  "title": "Rust project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Connect your Rust project to Tuist to track builds and tests, including doctests, and find flaky tests."
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

Tuist works with your existing Cargo project. You don't need to add a Rust dependency or change how your project builds.

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

Run `mise reshim` after adding the wrapper. You can then use `cargo build`, `cargo check`, and `cargo test` as usual. Mise runs them through Tuist for you.

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

Open **Tests** in the dashboard to see passed, failed, and ignored tests, including doctests. Cargo reports suite durations, but stable libtest does not expose per-test timings.

To run only doctests:

```sh
tuist cargo test --doc
```

Read more in <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link> and <.localized_link href="/guides/features/test-insights/flaky-tests/rust">Rust Flaky Tests</.localized_link>.
