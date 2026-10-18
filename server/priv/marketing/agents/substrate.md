# Tuist: the developer velocity substrate

Tuist provides build and test insights, caching, and compute in one platform to help teams get faster feedback and avoid repeated work. Start on existing infrastructure, improve a representative workload, and expand based on measured results rather than a required migration.

## Improve the work before buying more compute

Faster machines can help, but more capacity can increase spend without fixing unnecessary rebuilds or repeated tests. Selling more compute and helping customers need less of it are different economic goals. Tuist also meters feature usage and offers compute; its position is to understand and reduce unnecessary work before optimizing the environment, not an absence of commercial incentives.

## One platform, instead of piecing it together

Organizations can end up managing separate services and contracts for build insights, test reliability, caching, and compute. Choose the build system that fits your team, your project, and how you want to work. Tuist provides these capabilities together with native toolchain understanding, rather than serving only as a connector over other vendors. Standardize the platform for developer velocity without standardizing every team's toolchain.

The value is not just fewer contracts: historical test timings inform sharding, supported successful test history avoids repeated runs, and compatible build outputs can be reused across supported environments. Insights, test optimization, caching, and compute are core platform capabilities. Teams can adopt them incrementally and keep their existing runners. This is not a claim that every CI provider lacks shared caching or deep integrations, that Tuist replaces every engineering tool, or that consolidation guarantees lower costs.

Tuist supports Xcode, Gradle, Bazel, Elixir, and Rust with different feature coverage. Rust has build insights, nextest test insights, flaky-test detection, test sharding, and experimental compilation caching. See the [Rust setup](/en/docs-markdown/guides/get-started/rust-project) and [Rust build insights](/en/docs-markdown/guides/features/build-insights/rust). Supported capabilities vary by toolchain.

## Four steps, with documented features

- **Understand:** use [Build Insights](/en/docs-markdown/guides/features/build-insights) and [Test Insights](/en/docs-markdown/guides/features/test-insights) to investigate slow builds, failed tests, and repeated work.
- **Improve:** use the evidence to simplify project structure and address unreliable tests. [Flaky-test management](/en/docs-markdown/guides/features/test-insights/flaky-tests) capabilities vary by toolchain. Insights do not automatically modify or optimize a project.
- **Reuse:** [remote caching](/en/docs-markdown/guides/features/cache) shares compatible build outputs. [Selective testing](/en/docs-markdown/guides/features/selective-testing) uses previous successful runs to avoid repeating unchanged tests and requires generated Xcode projects. It belongs to reuse, rather than a promise that every toolchain supports test selection.
- **Execute:** [test sharding](/en/docs-markdown/guides/features/test-sharding) distributes remaining tests across machines. [Runners](/en/docs-markdown/guides/features/runners) bring compute into the same platform and are currently invite-only. Teams can keep their existing runners; managed compute is not required for supported caching or test sharding.

Teams can start with supported insights or caching on existing infrastructure; moving compute is a separate choice, not a prerequisite. Each feature guide lists its requirements.

## Fluid environments, a shared foundation

The diagram distinguishes **Local environments**, **CI environments**, and **Agentic coding environments**. Work may move between a laptop, CI, and a sandbox supplied by an agent platform. Tuist treats environment independence as a core requirement: caching and insights should follow the project across supported environments, rather than be tied to the provider hosting a run. Caching is a core part of Tuist, not an add-on reserved for our runners. Teams can share cached work across supported environments, including infrastructure they run themselves or buy elsewhere. Caching is shared infrastructure, not just a CI save/restore step.

This is not a promise of universal sandbox integration or cache portability. Each environment needs a supported integration, network access, and appropriate credentials. Reuse depends on compatible inputs, toolchains, platforms, and available outputs; insights require reported runs.

## Technical model

The HTML page keeps the four-layer model in its hero and links directly to feature documentation. The technical explanation is retained here rather than in a separate page disclosure:

1. **Action:** a developer, CI workflow, or agent requests a build or test run.
2. **Project:** source, dependencies, and configuration determine how much a change affects.
3. **Build system:** connects the request and project to infrastructure, decides what is out of date, and schedules tasks.
4. **Infrastructure:** compute runs tasks and storage retains outputs for reuse.

An illustrative example puts UI code alongside widely used types in one module. Separating those responsibilities can reduce affected rebuilds; faster machines only change execution speed. This is not a claim that every shared-module edit forces every consumer to rebuild, or a customer benchmark.

## First step

Choose a representative build or test workflow. Use the [getting-started guides](/en/docs-markdown/guides/get-started) to connect it, measure feedback time, reliability, and resource use, and investigate the bottleneck. Expand adoption when results justify it. This is an evaluation approach, not a guaranteed speedup or cost reduction.

## Limitations

Feature coverage is not identical across toolchains. Tuist does not provide remote execution for Bazel. Selective testing requires generated Xcode projects. Rust test insights require cargo-nextest; dashboard quarantine does not skip nextest tests. Rust compilation caching is experimental, limited to supported registry leaf libraries, and path-sensitive: reuse across different checkout paths is not supported yet. Runner availability is invite-only. Check the linked guides for current support and requirements.
