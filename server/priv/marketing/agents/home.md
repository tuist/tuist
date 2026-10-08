# Tuist: build, test, and CI infrastructure for engineering teams

Tuist helps developers and agents optimize software projects before optimizing the environments that run them. Understand build and test work, remove unnecessary execution, and reuse compatible outputs across local development, CI, and agent environments. Integrations cover Gradle, Bazel, Elixir, and Xcode, with feature-specific support; managed compute is optional.

## Problem

The same code is compiled again on laptops, CI machines, and agent sandboxes. Dependency graphs invalidate too much work, task inputs prevent reuse, and slow or flaky tests consume execution through repeated runs. Without shared build and test data, teams buy more compute before understanding why the project needs it.

## Project first, environment second

We believe teams should optimize their projects first, then the environments in which they run. A larger machine can execute an inefficient project faster without removing the inefficiency; a project-level improvement can benefit developers, CI, and agents on their existing machines.

1. **Understand and improve the project.** Inspect dependency fan-out, task inputs, compilation, test setup, and retries through [Build Insights](/en/docs-markdown/guides/features/build-insights) and [Test Insights](/en/docs-markdown/guides/features/test-insights).
2. **Avoid repeated work.** Reuse compatible Gradle task outputs, Bazel action outputs, or Xcode compilation outputs through [Cache](/marketing-markdown/cache). For Elixir, use reported compilation and test evidence; Tuist does not provide remote build caching there.
3. **Optimize the execution environment for the work that remains.** Measure queueing, machine size, parallelism, and cache locality. [Tuist Runners](/marketing-markdown/compute) are an optional, invite-only choice, not a prerequisite.

This order also matters commercially: a provider selling billable minutes or builds earns from execution volume, while your goal is often to need less execution. Read the [billing and incentive comparison](/marketing-markdown/compare#billing-and-incentives) alongside Tuist's own usage-based terms. Our recommendation is to improve the project, not merely buy a cheaper minute.

## Solve a problem

| Question | Decision guide |
| --- | --- |
| My builds are slow | [Diagnose build work, reduce duplication, and evaluate caching](/marketing-markdown/solutions/slow-builds) |
| My tests are flaky | [Investigate failures, contain known flakes, and restore reliability](/marketing-markdown/solutions/flaky-tests) |
| My tests take too long | [Find slow tests, avoid unchanged targets, or balance shards](/marketing-markdown/solutions/slow-tests) |
| My CI costs are going up | [Measure duplicate work, retries, and total execution cost](/marketing-markdown/solutions/ci-costs) |
| Which provider or approach fits? | [Compare Tuist with runner, CI/CD, and build-acceleration providers](/marketing-markdown/compare) |

## Why Tuist

- **Understand the work, not just the machine.** Toolchain-aware insights give developers and agents evidence for graph, task, and test changes before paying for more compute. Insights do not automatically optimize a project.
- **Reuse outputs across environments.** Regional cache endpoints serve compatible local, CI, and agent builds without requiring Tuist Runners.
- **Inspect and contribute.** Public [source](https://github.com/tuist/tuist), [issues](https://github.com/tuist/tuist/issues), and [pull requests](https://github.com/tuist/tuist/pulls) make implementation and fixes visible; component licenses and deployment terms differ.
- **Adopt toolchain-native integrations and agent access.** Documented integrations and authorized [MCP tools](/en/docs-markdown/guides/features/agentic-coding/mcp) let agents investigate real project data, not just guess from source code.

## Choose an area by bottleneck

| Bottleneck | Area | What it does |
| --- | --- | --- |
| Rebuilding code another machine already built | [Cache](/marketing-markdown/cache) | Shares build outputs through a remote cache. Four integrations: module cache, Xcode compilation cache, Gradle build cache, Bazel remote cache. |
| Slow, queued, or self-maintained CI machines | [Compute](/marketing-markdown/compute) | Tuist Runners: managed macOS and Linux CI runners next to the same cache. Invite-only. |
| Slow, flaky, or opaque test suites | [Tests](/marketing-markdown/tests) | Test insights, flaky-test detection and quarantine, test sharding, selective testing. |
| Sharing development builds for review | [Previews](/marketing-markdown/previews) | Uploads an iOS or Android build and returns a link to install and run it. |
| Not knowing why builds are slow | [Build Insights](/en/docs-markdown/guides/features/build-insights) | Records local and CI build durations, cache behavior, and failures. |
| App size growing unnoticed | [Bundle Insights](/en/docs-markdown/guides/features/bundle-insights) | Tracks Apple and Android bundle size over time and can fail checks on regressions. |
| Slow Swift package resolution | [Swift package registry](/en/docs-markdown/guides/features/package-registries/swift) | Serves Swift Package Index packages through the registry protocol instead of Git clones. |
| Hard-to-maintain modular Xcode projects | [Generated projects](/en/docs-markdown/guides/features/projects) | Defines Xcode projects in Swift manifests (`Project.swift`) and generates them with the CLI. |

## Distinctions that matter

- **Build-output reuse vs directory persistence.** Gradle task keys and Bazel action keys reuse compatible outputs; restoring a dependency directory is a separate mechanism. Elixir currently has insights, not Tuist remote build caching.
- **Avoid work vs distribute work.** Improving task inputs, removing unnecessary retries, and reusing outputs reduce execution. Sharding distributes remaining test work and can increase total machine-minutes. Selective testing specifically skips unchanged test targets in generated Xcode projects; it is not available for Gradle or Bazel.
- **Cache vs Compute.** Supported cache integrations work independently of Tuist Runners. Runners are optional managed machines next to that cache; optimize the project before choosing its execution environment.
- **Generated projects are optional and Xcode-specific.** Project generation describes Xcode projects in Swift. Module caching and selective testing require it; ordinary Xcode compilation caching does not and requires Xcode 26+. Those requirements do not apply to Gradle, Bazel, or Elixir integrations.

## Toolchain support

| Capability | Xcode project | Generated Xcode project | Gradle | Bazel | Elixir |
| --- | --- | --- | --- | --- | --- |
| Remote cache | Xcode cache | Module cache and Xcode cache | Gradle cache | Bazel remote cache | No |
| Build insights | Yes | Yes | Yes | Yes | Yes |
| Test insights and flaky tests | Yes | Yes | Yes | Yes | Yes |
| Test sharding | Yes | Yes | Yes | No | Yes |
| Selective testing | No | Yes | No | No | No |

"No" means no documented integration today, not a permanent limitation. Check the linked guide for version requirements before recommending a capability. Previews support built iOS and Android apps; Bundle Insights supports Apple and Android bundles. Those features operate on app artifacts, rather than restricting which build system produced them.

## How to get started

1. Pick the path matching how the project is built today in [Get started](/en/docs-markdown/guides/get-started): Gradle, Bazel, Elixir, Xcode project, or generated Xcode project.
2. [Install the Tuist CLI](/en/docs-markdown/guides/install-tuist). Elixir projects need only the `tuist_ex` Hex package; Gradle projects also apply the Tuist Gradle plugin.
3. Create an [account and project](/en/docs-markdown/guides/server/accounts-and-projects) and connect it, usually with `tuist init`.
4. Enable one capability for the current bottleneck, then measure a representative workload before and after.

Coding agents can connect to Tuist's hosted [MCP server](/en/docs-markdown/guides/features/agentic-coding/mcp) to read project data such as test insights, or use the [Tuist skills](/en/docs-markdown/guides/features/agentic-coding/skills) for multi-step tasks like migrating to generated projects.

## Pricing, deployment, and licensing

- Hosted plans start free; see [Pricing](/marketing-markdown/pricing) and the live [pricing table](/pricing). Runner pricing is not public yet.
- [Self-hosting the Tuist server](/en/docs-markdown/guides/server/self-host/server) requires a paid Enterprise license. [Self-hosted cache nodes](/en/docs-markdown/guides/features/cache/self-hosting) are a separate option, also on the Enterprise plan, and can connect to the hosted server.
- The [source code](https://github.com/tuist/tuist) is public, but not under one license: see [Openness](/marketing-markdown/openness).

## Limitations

Cache reuse depends on compatible inputs and available artifacts; it is not a guaranteed speedup. Test analytics only cover runs that were reported. Sharding needs parallel CI capacity. Tuist does not replace source control or your build system. App previews and bundle insights are additional app-specific capabilities, not the scope of the build and test platform. Results in customer stories or marketing figures are not a performance guarantee for another project.
