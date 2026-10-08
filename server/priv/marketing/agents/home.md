# Tuist: build, test, and CI infrastructure for app teams

Tuist helps developers and agents understand and reduce build and test work, wherever that work runs. Separately adoptable capabilities include remote caching, build and test insights, test acceleration, app previews, and optional managed CI runners. Most integrate with an existing Xcode, Gradle, Bazel, or Elixir setup; support differs by toolchain.

## Problem

The same code is compiled again on laptops, CI machines, and agent sandboxes. Test suites grow slower and flakier, CI time goes to queues and cold machines, and sharing a development build means a store upload or a local checkout. Without shared build and test data, teams guess where the time goes.

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

- **Generated projects are optional.** Project generation is a CLI capability for describing Xcode projects in Swift. Most server features (Xcode compilation cache, insights, previews, sharding, registry) work with an existing Xcode project. Only the **module cache** and **selective testing** require Tuist-generated Xcode projects.
- **Module cache vs Xcode compilation cache.** The module cache replaces whole targets with prebuilt `.xcframework` binaries at generation time. The Xcode cache reuses compiler outputs during an Xcode 26+ build and needs no generation. They are complementary.
- **Selective testing vs sharding.** Selective testing skips test targets whose inputs did not change; sharding splits the tests that do run across parallel CI machines. One reduces work, the other spreads it.
- **Cache vs Compute.** The cache works from any machine. Runners are optional managed machines that sit next to that cache; you do not need runners to use the cache.

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

1. Pick the path matching how the project is built today in [Get started](/en/docs-markdown/guides/get-started): Xcode project, generated Xcode project, Gradle, Bazel, or Elixir.
2. [Install the Tuist CLI](/en/docs-markdown/guides/install-tuist). Elixir projects need only the `tuist_ex` Hex package; Gradle projects also apply the Tuist Gradle plugin.
3. Create an [account and project](/en/docs-markdown/guides/server/accounts-and-projects) and connect it, usually with `tuist init`.
4. Enable one capability for the current bottleneck, then measure a representative workload before and after.

Coding agents can connect to Tuist's hosted [MCP server](/en/docs-markdown/guides/features/agentic-coding/mcp) to read project data such as test insights, or use the [Tuist skills](/en/docs-markdown/guides/features/agentic-coding/skills) for multi-step tasks like migrating to generated projects.

## Pricing, deployment, and licensing

- Hosted plans start free; see [Pricing](/marketing-markdown/pricing) and the live [pricing table](/pricing). Runner pricing is not public yet.
- [Self-hosting the Tuist server](/en/docs-markdown/guides/server/self-host/server) requires a paid Enterprise license. [Self-hosted cache nodes](/en/docs-markdown/guides/features/cache/self-hosting) are a separate option, also on the Enterprise plan, and can connect to the hosted server.
- The [source code](https://github.com/tuist/tuist) is public, but not under one license: see [Openness](/marketing-markdown/openness).

## Limitations

Cache reuse depends on compatible inputs and available artifacts; it is not a guaranteed speedup. Test analytics only cover runs that were reported. Sharding needs parallel CI capacity. Tuist does not replace source control, your build system, or store distribution. Results in customer stories or marketing figures are not a performance guarantee for another project.
