---
title: "Cut Rust compile time with a Tuist Cargo cache"
category: "product"
tags: ["product", "rust", "cargo"]
excerpt: "Tuist now cuts Rust compile time in CI with an experimental Cargo cache, and adds Cargo build time insights, test insights, flaky tests, and code coverage."
author: pepicrft
og_image_path: /marketing/images/blog/2026/11/13/rust/og.png
cta_title: "Cut your Rust compile time in CI."
live: true
---

Something big is happening in how we build software: with AI, the programming language is becoming an implementation detail. When an agent can write, translate, and test most of the code, the cost of writing it stops being the main input into which language and framework to use. And that's making many organizations question abstractions that existed largely because development time was expensive.

React Native, Flutter, and Electron are good examples. They let a team write a feature once and ship it on several platforms, and that trade-off made a lot of sense when building the same thing twice was the bottleneck. Shopify went all-in on React Native in 2020. This year they [explained why they're going back to Swift and Kotlin](https://shopify.engineering/back-to-native): agents now do enough of the implementation, translation, testing, and review work that sharing code is no longer the deciding factor. They then rebuilt the Shopify app in 12 weeks.

Discord is going in a similar direction, with a twist. They've been using Rust since 2018, and now they're [moving their clients off Electron and React Native](https://www.theverge.com/news/1027379/discord-ditching-electron-web-app): one Rust core shared by the desktop app and native interfaces on iOS and Android.

<.live_component module={TuistWeb.Marketing.Components.Posts.Rust.XPost} id="discord-desktop-post" post="desktop" />

<.live_component module={TuistWeb.Marketing.Components.Posts.Rust.XPost} id="discord-ios-post" post="ios" />

Moving more code to Rust has a well-known cost, though: compile time. A compiler that checks this much before your code runs has a lot of work to do, and the more code agents write, the more there is to compile and test.

Today we're bringing Tuist to Rust. `tuist cargo` runs the Cargo commands you already use and adds:

- A build cache that reuses compilations across CI runs, fresh clones, and branches, including your own crates.
- Build insights, down to every `rustc` invocation and how long it took.
- Test insights for `cargo test`, with flaky test detection and quarantine.
- Test sharding and code coverage.

We tried it on Codex, OpenAI's open-source coding agent, whose Rust workspace has more than 130 crates and around 1,500 dependencies. We took two real commits from its `main` branch, [one that changes `codex-cli`](https://github.com/openai/codex/commit/3f2603f2a2) and [one that changes `codex-core`](https://github.com/openai/codex/commit/1c76c0bc08), and built each from a clean target directory, the way a CI job would:

<.live_component module={TuistWeb.Marketing.Components.Posts.Rust.BuildTimes} id="rust-build-times" />

After the `codex-cli` change, Tuist reused 162 of the 163 compilations and finished in 22 seconds instead of almost 3 minutes. `codex-core` sits underneath almost everything, so a change there still recompiles 28 crates, and `codex-core` alone takes about a minute. When nothing changed at all, the same clean build took 4 seconds.

## Getting started with Tuist and Cargo

Sign in or create an account at [tuist.dev](https://tuist.dev), then create a project in the dashboard and choose **Cargo (Rust)** as its build system. Install the [Tuist CLI](https://tuist.dev/en/docs/guides/install-tuist), version 4.218.0 or later, and point your workspace's `Cargo.toml` at the project:

```toml
[workspace.metadata.tuist]
project = "account/project"
```

Cargo leaves `metadata` tables to other tools, so your build doesn't change, and the configuration lives next to the rest of your project's. If you'd rather keep it in its own file, a `tuist.toml` at the root of the repository works too.

Log in with `tuist auth login`, and run your Cargo commands through Tuist:

```bash
tuist cargo build --workspace
tuist cargo test --workspace
```

Tuist passes your arguments to Cargo as they are, including features, toolchains, and test filters. Cargo keeps its output and exit code, even if a report can't be uploaded. There's no Rust dependency or Cargo plugin to add.

If you'd rather keep typing `cargo`, [mise](https://mise.jdx.dev/) can wrap it for you:

```toml
[wrappers.cargo]
command = "tuist"
args = ["cargo"]
```

This is particularly useful with coding agents: they keep running `cargo build` and `cargo test` without being reminded to add a prefix. In CI, authenticate through your provider's OpenID Connect identity or a token. The [Rust guide](https://tuist.dev/en/docs/guides/get-started/rust-project) covers the details.

## Cutting Rust compile time with a Cargo cache

CI keeps compiling the same versions of the same dependencies, and when you switch branches or clean the target directory, you compile them again too. `tuist cargo build` caches eligible compilations, both locally and through [Kura](/blog/2026/09/14/kura), our distributed cache, and `tuist cargo check` and `tuist cargo clippy` get the same treatment. Tuist hooks in through Cargo's [rustc wrapper](https://doc.rust-lang.org/cargo/reference/config.html#buildrustc-wrapper), so your toolchain and `Cargo.toml` files stay as they are.

Before Cargo starts, Tuist restores dependency units that an earlier build produced with the same toolchain, profile, and configuration, so Cargo finds them up to date. Cargo stays in charge of deciding what to rebuild. Then, for each compilation Cargo still runs, Tuist looks for matching outputs, first locally and then remotely, and compiles normally on a miss. That includes your own crates, which Cargo compiles incrementally in the `dev` profile and sccache [can't cache](https://github.com/mozilla/sccache#rust).

Tuist can't put Cargo in a sandbox, so it watches what each compilation reads instead. Library crates are keyed by the sources the compiler reports, together with the toolchain. Build scripts, procedural macros, and native code are keyed by every file, directory, and environment variable they actually read, on Apple silicon Macs and on Linux with glibc. When a compilation does something Tuist can't account for, such as reaching the network, Tuist doesn't cache it.

The Codex numbers above are medians of five runs on an Apple silicon Mac with `CI` set, which since Cargo 1.99 also turns incremental compilation off, and a local cache filled by the commit before each change. Filling an empty cache costs something: that first build took 3m 59s, against about 2m 55s for plain Cargo. On your own machine, Cargo's incremental compilation already takes care of the crate you're editing, so the cache pays off when the target directory starts cold. The [Cargo build cache guide](https://tuist.dev/en/docs/guides/features/cache/rust) lists what's cached today.

We believe Cargo will eventually do this itself. The Cargo team is already [working towards a build cache shared across workspaces](https://goals.rust-lang.org/2026/cargo-cross-workspace-cache.html). Until it lands, we want Rust teams to have the most productive experience we can give them.

## Build and test insights

Every `tuist cargo` command also reports to Tuist, so you can see where the time goes and keep the codebase healthy as it grows. The screenshots below are the real Tuist dashboard with our Codex runs.

![A Codex build showing its compiler jobs sorted by duration](/marketing/images/blog/2026/11/13/rust/build-detail.webp)

*An incremental build of Codex at commit `662daab`. `codex_core` took 2 minutes and 2 seconds of the build's 3 minutes and 24 seconds, and the crates that depend on it, like `codex_tui` and `codex_app_server`, only started once it finished.*

With Rust, Tuist supports:

- [Build insights](https://tuist.dev/en/docs/guides/features/build-insights/rust) for every Cargo command, with its duration, branch, commit, and Rust version, plus each `rustc` invocation with its timing, warnings, and errors. Agents can read them through `tuist build cargo list`, the REST API, and our MCP server.
- Test insights for plain `cargo test` on stable Rust, including unit tests, integration tests, and doctests. Stable libtest only reports how long each test binary took, so Tuist records suite durations, not per-test timings.
- [Flaky test detection](https://tuist.dev/en/docs/guides/features/test-insights/flaky-tests/rust) across CI runs on the same commit, with muting and skipping from the dashboard. Muted tests keep running but don't fail the command, and if Tuist can't fetch the quarantine state, it runs without it rather than hiding failures.
- Test sharding by Cargo target, planned from historical durations.
- Code coverage through LLVM's source-based instrumentation, merged across a commit's runs and shards for each package and file.

![The Codex test cases dashboard with a muted test](/marketing/images/blog/2026/11/13/rust/flaky-tests.webp)

*No Codex test was flaky in our runs, so we muted `cancel_exits_run` by hand to show what quarantine looks like. The test history records who muted it and when.*

## Keeping the team in the loop

Tuist can also post to a Slack channel when a test becomes flaky, when test runs get slower, and with a regular report on how the project is doing.

<.live_component module={TuistWeb.Marketing.Components.Posts.Rust.SlackMessages} id="codex-slack-messages" />

*The daily report is the one Tuist generated for the Codex project in this post. The flaky test message shows what the default automation posts; no Codex test was flaky in our runs.*

Flaky test events are also available through our [MCP Events interface](https://tuist.dev/en/docs/guides/features/agentic-coding/mcp#events), so an agent can start investigating a test's history before anyone notices it in CI.

## What's next

We're working on test selection based on coverage: using what each test exercises to run only the tests affected by a change, instead of the whole suite. Coverage is the first step, and it's already there for Rust. We're also looking into remote execution, which spreads a build's compilations across many machines, so it can use more cores than any single runner has.

If you run CI on [Tuist Runners](/blog/2026/11/04/runners), we already take this further: the cache nodes sit in the same rack as the machines that build, so every cache request stays on the local network. If you'd like to try it with your Rust project, [reach out](mailto:contact@tuist.dev).

And if you want to keep your project defined in `Cargo.toml` and go further, there's [Once](https://github.com/tuist/once), our own build system. It loads Cargo workspaces as they are and adds remote caching and remote execution, without asking you to describe your project again.

## Come build with us

If you maintain an open-source Rust project, our [open-source program](/blog/2024/04/25/tuist-cloud-free-for-open-source) gives you free access to these features. [Send us your repository and Tuist account handle](mailto:contact@tuist.dev), and we'll help you get set up.

And if you're moving more of your code to Rust at work, we'd love to hear about it. Where does the time go in your builds and tests? What have you had to build yourselves? To the folks at Discord: we've been following the new client with a lot of excitement, and we'd love to help you keep those builds fast as it grows. You can [book a call with us](https://cal.tuist.dev/team/tuist/tuist) to talk about it.
