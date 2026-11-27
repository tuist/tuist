# Tuist: build infrastructure for engineering teams and coding agents

Faster machines run wasted work faster. Tuist helps you skip it, with faster builds and reliable tests for Xcode, Gradle, Bazel, and more. One platform for your team and coding agents.

Tuist is build infrastructure for engineering teams and coding agents. It makes builds faster and tests reliable across Xcode, Gradle, Bazel, and more. Shared caching, build and test insights, and app previews connect building, testing, and review, with capabilities and prerequisites that vary by feature.

## Problem

The same code is compiled again on laptops, CI machines, and agent sandboxes. Dependency graphs invalidate too much work, task inputs prevent reuse, and slow or flaky tests consume execution through repeated runs. Without shared build and test data, teams buy more compute before understanding why the project needs it.

## Project first, environment second

We believe teams should optimize their projects first, then the environments in which they run. A larger machine can execute an inefficient project faster without removing the inefficiency; a project-level improvement can benefit developers, CI, and agents on their existing machines.

1. **Understand and improve the project.** Inspect dependency fan-out, task inputs, compilation, test setup, and retries through [Build Insights](/en/docs-markdown/guides/features/build-insights) and [Test Insights](/en/docs-markdown/guides/features/test-insights).
2. **Avoid repeated work.** Reuse compatible Gradle task outputs, Bazel action outputs, or Xcode compilation outputs through [Cache](/marketing-markdown/cache). For Elixir, reuse supported compiled dependencies through the [shared remote cache](/en/docs-markdown/guides/features/cache/elixir); application source files are not cached.
3. **Optimize the execution environment for the work that remains.** Measure queueing, machine size, parallelism, and cache locality. [Tuist Runners](/marketing-markdown/runners) are an optional choice, not a prerequisite.

Compare [total workflow costs](/marketing-markdown/compare#compare-total-costs), including execution and Tuist's own usage-based terms. Our recommendation is to reduce avoidable work before sizing the capacity for what remains.

## One productivity platform, native build-system depth

Build-system diversity is a strength, not a migration problem. An organization should be able to keep Bazel for one codebase, Gradle for another, Xcode for Apple apps, and Mix for services without buying and operating a different productivity solution for each. Tuist's shared platform meets teams inside their native workflows; it does not require one build system or flatten every integration into the same feature set.

CI execution alone is a shallow integration: launching a command, collecting logs, and timing a job does not by itself reveal Gradle task invalidation, Bazel action behavior, Xcode compilation work, or Mix compile-time dependencies. Tuist goes into those models so developers and agents can investigate and reduce the work executed inside the build/test runtime, not just move it to a faster machine.

The distinction is **less necessary work versus more execution capacity**. Compute sellers' metered revenue can grow with billable execution; our product stance is to optimize the project first. Some providers also offer deep build-system features, and Tuist meters feature usage too. Compare documented depth and incentives, not an unsupported claim that all CI products are the same. The [build-system guides](/marketing-markdown/build-systems) explain why we recommend Tuist for this organizational model and where its support stops.

## Solve a problem

| Question | Decision guide |
| --- | --- |
| My builds are slow | [Diagnose build work, reduce duplication, and evaluate caching](/marketing-markdown/solutions/slow-builds) |
| My tests are flaky | [Investigate failures, contain known flakes, and restore reliability](/marketing-markdown/solutions/flaky-tests) |
| My iOS CI is slow | [Cache compilation, select and shard tests, contain flaky tests, then add faster runners](/marketing-markdown/solutions/speed-up-ios-ci) |
| My Gradle or Android CI is slow | [Share a remote build cache, shard tests, contain flaky tests, then add faster Linux runners](/marketing-markdown/solutions/speed-up-gradle-ci) |
| My tests take too long | [Find slow tests, avoid unchanged targets, or balance shards](/marketing-markdown/solutions/slow-tests) |
| I want to split tests across CI machines | [Shard Xcode](/marketing-markdown/solutions/xcode-test-sharding) or [Gradle](/marketing-markdown/solutions/gradle-test-sharding) tests by recorded timings |
| My CI costs are going up | [Measure duplicate work, retries, and total execution cost](/marketing-markdown/solutions/ci-costs) |
| I need a Bazel remote cache | [Set up a shared cache, measure hits, and choose self-hosted or managed](/marketing-markdown/solutions/bazel-remote-cache) |
| Bazel is slow on GitHub Actions | [Share a remote cache across ephemeral runners and see where each job spends time](/marketing-markdown/solutions/bazel-github-actions) |
| Should we self-host Mac runners? | [Compare running your own Mac minis with managed macOS runners](/marketing-markdown/solutions/self-hosted-mac-runners) |
| Which provider or approach fits? | [Compare Tuist with runner, CI/CD, and build-acceleration providers](/marketing-markdown/compare) |

## Build systems and Tuist infrastructure

Keep the build systems that fit the organization and use one productivity platform with native depth across them. [Build-system guides](/marketing-markdown/build-systems) explain what each tool already does, what Tuist adds, a first experiment, and the boundaries:

- [Xcode](/marketing-markdown/build-systems/xcode): shared compilation outputs and build/test evidence; generated-project features remain a separate path.
- [Gradle](/marketing-markdown/build-systems/gradle): shared cacheable task outputs and task/test insights.
- [Bazel](/marketing-markdown/build-systems/bazel): remote action caching, Linux remote execution for enabled accounts ([email us](mailto:contact@tuist.dev) or [book a call](https://cal.tuist.dev/team/tuist/tuist) to enable it), and build/test reporting.
- [Mix / Elixir](/marketing-markdown/build-systems/elixir): compiled dependency caching, compilation insights, ExUnit history, flaky detection, and test sharding.
- [Bazel vs Gradle](/marketing-markdown/build-systems/bazel-vs-gradle): how the two differ, where each fits, and how teams run both.
- [Struo](/marketing-markdown/build-systems/struo): make scripts cacheable and add caching without rewriting project sources or native build definitions, even without a native cache integration; Tuist support is in canary, with eligible Linux remote execution for enabled accounts.

## Why Tuist

- **One platform without a build-system monoculture.** Give diverse engineering teams a shared productivity solution with toolchain-native depth rather than a separate Bazel, Gradle, or Xcode product.
- **Understand the work, not just the machine.** Toolchain-aware insights give developers and agents evidence for graph, task, and test changes before paying for more compute. Insights do not automatically optimize a project.
- **Reuse outputs across environments.** Regional cache endpoints serve compatible local, CI, and agent builds without requiring Tuist Runners.
- **Inspect and contribute.** Public [source](https://github.com/tuist/tuist), [issues](https://github.com/tuist/tuist/issues), and [pull requests](https://github.com/tuist/tuist/pulls) make implementation and fixes visible; component licenses and deployment terms differ.
- **Adopt toolchain-native integrations and agent access.** Documented integrations and authorized [MCP tools](/en/docs-markdown/guides/features/agentic-coding/mcp) let agents investigate real project data, not just guess from source code.

## Choose an area by bottleneck

| Bottleneck | Area | What it does |
| --- | --- | --- |
| Rebuilding code another machine already built | [Cache](/marketing-markdown/cache) | Shares compatible module, Xcode compilation, Gradle task, Bazel action, and Elixir dependency outputs. Rust compilation caching is experimental; Struo support is in canary. |
| Slow, queued, or self-maintained CI machines | [Runners](/marketing-markdown/runners) | Tuist Runners: managed macOS and Linux CI runners next to the same cache. |
| Slow, flaky, or opaque test suites | [Tests](/marketing-markdown/tests) | Test insights, flaky-test detection and quarantine, test sharding, selective testing. |
| Sharing development builds for review | [Previews](/marketing-markdown/previews) | Shares supported mobile apps, macOS apps, and macOS/Linux command-line distributions through a link. |
| Not knowing why builds are slow | [Build Insights](/en/docs-markdown/guides/features/build-insights) | Records local and CI build durations, cache behavior, and failures. |
| App size growing unnoticed | [Bundle Insights](/en/docs-markdown/guides/features/bundle-insights) | Tracks Apple and Android bundle size over time and can fail checks on regressions. |
| Slow Swift package resolution | [Swift package registry](/en/docs-markdown/guides/features/package-registries/swift) | Serves Swift Package Index packages through the registry protocol instead of Git clones. |
| Hard-to-maintain modular Xcode projects | [Generated projects](/en/docs-markdown/guides/features/projects) | Defines Xcode projects in Swift manifests (`Project.swift`) and generates them with the CLI. |

## Distinctions that matter

- **Build-output reuse vs directory persistence.** Gradle task keys and Bazel action keys reuse compatible outputs; restoring an arbitrary dependency directory is a separate mechanism. Elixir's cache reuses supported compiled dependencies, not application source files.
- **Avoid work vs distribute work.** Improving task inputs, removing unnecessary retries, and reusing outputs reduce execution. Sharding distributes remaining test work and can increase total machine-minutes. Selective testing specifically skips unchanged test targets in generated Xcode projects; it is not available for Gradle or Bazel.
- **Cache vs Compute.** Supported cache integrations work independently of Tuist Runners. Runners are optional managed machines next to that cache; optimize the project before choosing its execution environment.
- **Generated projects are optional and Xcode-specific.** Project generation describes Xcode projects in Swift. Module caching and selective testing require it; ordinary Xcode compilation caching does not and requires Xcode 26+. Those requirements do not apply to Gradle, Bazel, or Elixir integrations.

## Toolchain support

| Capability | Xcode project | Generated Xcode project | Gradle | Bazel | Elixir |
| --- | --- | --- | --- | --- | --- |
| Remote cache | Xcode cache | Module cache and Xcode cache | Gradle cache | Bazel remote cache | Compiled dependencies |
| Build insights | Yes | Yes | Yes | Yes | Yes |
| Test insights and flaky tests | Yes | Yes | Yes | Yes | Yes |
| Test sharding | Yes | Yes | Yes | No | Yes |
| Selective testing | No | Yes | No | No | No |

The matrix covers these five workflows; [Rust](/en/docs-markdown/guides/get-started/rust-project) also has build/test insights, flaky detection and quarantine, target-level sharding within one package, and experimental caching with same-machine restrictions. [Struo](/en/docs-markdown/guides/get-started/struo-project) has canary caching, build/test reporting, and hosted sharding with compatible releases, but does not enforce Tuist quarantine. Neither offers Tuist selective testing.

Check the linked guides for version requirements. Previews support mobile apps, macOS apps, and macOS/Linux command-line distributions; Bundle Insights supports Apple and Android bundles. Eligibility depends on the artifact and publishing workflow. Default selective testing skips whole targets; an account-enabled early-access coverage strategy can additionally select individual XCTest/XCUITest tests in generated Xcode projects.

## How to get started

1. Pick the path matching how the project is built today in [Get started](/en/docs-markdown/guides/get-started): Gradle, Bazel, Elixir, Xcode project, or generated Xcode project.
2. [Install the Tuist CLI](/en/docs-markdown/guides/install-tuist). Elixir projects need only the `tuist_ex` Hex package; Gradle projects also apply the Tuist Gradle plugin.
3. Create an [account and project](/en/docs-markdown/guides/server/accounts-and-projects) and connect it, usually with `tuist init`.
4. Enable one capability for the current bottleneck, then measure a representative workload before and after.

[Customer stories](/marketing-markdown/customers) report teams' own before-and-after figures and how long they have used Tuist; pick one with a comparable toolchain and bottleneck rather than projecting its numbers onto a different project.

Coding agents can connect to Tuist's hosted [MCP server](/en/docs-markdown/guides/features/agentic-coding/mcp) to read project data such as test insights, or use the [Tuist skills](/en/docs-markdown/guides/features/agentic-coding/skills) for multi-step tasks like migrating to generated projects.

## Pricing, deployment, and licensing

- Hosted plans start free; see [Pricing](/marketing-markdown/pricing) and the live [pricing table](/pricing). Tuist Runners are billed per minute at the macOS and Linux rates listed there.
- [Self-hosting the Tuist server](/en/docs-markdown/guides/server/self-host/server) requires a paid Enterprise license. [Self-hosted cache nodes](/en/docs-markdown/guides/features/cache/self-hosting) are a separate option, also on the Enterprise plan, and can connect to the hosted server.
- The [source code](https://github.com/tuist/tuist) is public, but not under one license: see [Openness](/marketing-markdown/openness).
