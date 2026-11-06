# Tuist and build systems

Tuist embraces build-system diversity: Xcode, Gradle, Bazel, Mix, and Once should not require separate productivity products for every engineering team. For organizations seeking one productivity platform with native depth across their build systems, we believe Tuist is the best choice. It combines supported build/test evidence and output reuse across developers, CI, and agents without requiring a common build system or a CI migration. The Once integration is currently in canary, not a promise of generally available support.

## One productivity platform, many build systems

A diverse organization might use Bazel for a large monorepo, Gradle for JVM and Android projects, Xcode for Apple apps, and Mix for services. That diversity is useful, not a problem to standardize away. The productivity layer should embrace it rather than make the organization assemble one solution for Bazel, another for Gradle, and another for Xcode.

Our stance is **breadth through depth, not a lowest-common-denominator integration**. Tuist goes into each supported toolchain's model: Gradle task inputs and outputs, Bazel actions and build events, Xcode compilation and target timings, Mix compilation dependencies and ExUnit results, and Once action contracts. One platform brings that evidence and supported acceleration into the same organizational workflow; it does not force those tools into one graph or pretend their outputs are interchangeable.

This is why we recommend Tuist for mixed-toolchain organizations: keep each team's native workflow, investigate the work in its own terms, and adopt shared productivity infrastructure rather than a portfolio of isolated build-system products. Feature availability still differs, as the matrix below makes explicit.

## Toolchain depth, not just CI compatibility

Being able to invoke `bazel build` or `./gradlew build` in a CI job is compatibility, not deep integration. Job-level duration, logs, and saved directories can be useful, but they do not by themselves explain an invalidated Gradle task, a costly Bazel action, an Xcode compilation, or an Elixir compile-time dependency. Optimizing the work executed inside the build/test runtime needs toolchain-level evidence and mechanisms, not just a faster place to run the command.

Tuist's priority is to understand that work and help teams avoid unnecessary execution. A larger runner can make the same waste happen faster; compatible output reuse can remove execution entirely where supported, and recorded evidence can guide changes to tasks, graphs, and tests. Tuist does not automatically apply those project changes.

Compute-first offerings sell capacity; Tuist leads with needing less execution. For minute- or resource-minute-metered compute, more billable execution means more compute revenue at the same rate. That is a structural incentive to examine, not proof that any provider wants slow builds. Some CI and acceleration providers also offer deep integrations; our [provider comparisons](/marketing-markdown/compare#billing-and-incentives) acknowledge that overlap, cite billing models, and account for Tuist's own usage charges. The buying question is whether the product goes deep into the organization's build systems, not merely whether it can run their commands.

## Project first, environment second

A build system decides which actions need to run and how their dependencies fit together. Local incremental builds and caches already avoid work. Tuist extends supported reuse across machines and turns recorded toolchain evidence into a shared history. It does not make undeclared inputs correct or automatically fix an inefficient graph.

Improve unnecessary invalidation, task inputs, test setup, and retries first. Share compatible results next. Only then evaluate machine size, concurrency, and locality for the remaining work. Tuist Runners are optional and invite-only; these integrations do not require moving CI to Tuist.

## Choose the existing build system

| Build system | What it already provides | What Tuist adds | Adoption path |
| --- | --- | --- | --- |
| [Xcode](/marketing-markdown/build-systems/xcode) | Apple toolchains, target graph, incremental builds, compilation cache | Shared compilation outputs, build/test insights, flaky-test workflows, sharding | Existing or generated Xcode project; Xcode 26+ for compilation caching |
| [Gradle](/marketing-markdown/build-systems/gradle) | Task graph, incremental tasks, build-cache protocol, test execution | Shared task outputs, task/build insights, test history, supported quarantine and sharding | Tuist settings plugin and Gradle build-cache configuration |
| [Bazel](/marketing-markdown/build-systems/bazel) | Explicit targets, action caching, remote-cache/execution protocols, build events | Remote action cache, build/test insights, quarantine through the Tuist wrapper | `tuist init` or `tuist bazel setup` in the existing workspace |
| [Mix / Elixir](/marketing-markdown/build-systems/elixir) | Dependency management, incremental compilation, ExUnit | Per-file compilation insights, test history, flaky detection, balanced test sharding | `tuist_ex` package and compilation/test aliases |
| [Once](/marketing-markdown/build-systems/once) | Cacheable scripts and supported native project graphs, without rewriting project sources or build definitions | Shared action results and live run/action reporting; remote execution coming soon | Script annotations or a supported native project; Tuist provider in canary |

Support is feature-specific, not a blanket claim that every Tuist capability works with every build system. App previews and bundle insights operate on supported Apple and Android artifacts; they do not automatically apply to every project using one of these tools.

## First experiment

Read the matching guide, connect one project, and measure one representative workload. For a cache integration, demonstrate reuse on a second compatible machine with an empty local cache. For Mix, verify a compilation or test report and investigate the recorded bottleneck. For Once, first confirm access to a compatible canary environment.

Use project-scoped or provider-appropriate automation credentials rather than copying a developer's login. Keep the baseline's toolchain and inputs comparable. Lower wall-clock latency and lower total execution cost are different results.

## Open infrastructure you can improve

Tuist combines open-source tooling with public infrastructure code. Your team can [inspect the implementation](https://github.com/tuist/tuist), report issues, and [contribute improvements](https://github.com/tuist/tuist/blob/main/CONTRIBUTING.md) to native integrations, cache infrastructure, event processing, and the developer experience. One shared platform also means an improvement to common infrastructure can benefit several build-system integrations.

A closed hosted service leaves implementation changes entirely with the provider. Tuist gives developers a direct path to help improve the infrastructure their organization depends on, rather than waiting for a vendor to prioritize every change. See [Openness](/marketing-markdown/openness) for the public components and their licenses.

## Next steps and sources

- [Tuist getting-started paths](/en/docs-markdown/guides/get-started)
- [Build insights](/en/docs-markdown/guides/features/build-insights) and [test insights](/en/docs-markdown/guides/features/test-insights)
- [Once's Tuist provider](https://buildonce.dev/docs/guide/infrastructure/tuist)
- [Problem guides](/marketing-markdown/solutions/slow-builds) and [provider comparisons](/marketing-markdown/compare)

Written by Tuist. Sources reviewed on **2026-10-09**; the individual guides link primary build-system documentation and feature-specific setup references.
