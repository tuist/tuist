# Tuist with Bazel

Tuist brings Bazel-native depth to one productivity platform for organizations with diverse build systems. Its remote action cache and build/test insights use protocols Bazel already supports, alongside the platform's supported Gradle, Xcode, Mix, and canary Once workflows. Keep your `BUILD` files, language rules, toolchains, and ordinary build commands; no migration to generated Xcode projects or Tuist Runners is required.

## One productivity platform, native depth

Bazel teams should not have to choose between specialist depth, organizational breadth, and a good developer experience. We believe Tuist is the best choice for organizations seeking one productivity platform across these build systems: Bazel-native evidence and reuse, a workflow the whole team can use, and the same platform for Gradle, Xcode, Mix, and Once.

## Depth, breadth, and developer experience. No compromise.

Bazel-only solutions can provide real depth into actions and build events, but a Bazel-only product still leaves the organization buying another solution for Gradle or Xcode. That specialization can also come with a fragmented, specialist-heavy developer experience: separate tools and interfaces, more onboarding, and low-level diagnostics that developers must turn into an answer themselves. Depth should make the development loop easier, not reserve useful information for a few build experts.

At the other end, a CI provider may support Bazel by launching `bazel build`, retaining logs, and reporting job duration. That is command compatibility, not enough toolchain depth to guide graph optimization. Finding costly actions and critical-path bottlenecks needs Bazel-level evidence, not just a faster runner executing the same graph. Providers that also offer deep Bazel integrations should be evaluated on that actual depth, not grouped with command-only support.

**Our stance is no compromise on native depth, cross-build-system breadth, or developer experience.** Tuist combines:

- **Depth to improve the work.** Bazel build events, recorded action and target counts, cache behavior, timelines, and critical-path summaries help teams identify where to investigate their graph. Shared compatible action outputs avoid executing work another machine already performed.
- **Breadth for the organization.** Keep Bazel where it fits without forcing Gradle, Xcode, or Mix teams to migrate or buy disconnected productivity products. The [cross-build-system platform](/marketing-markdown/build-systems) respects each toolchain's native model.
- **A developer experience built around answers.** Connect the workspace, keep normal `bazel build` and `bazel test` commands, and inspect structured invocations and test history in the dashboard. Developers and agents can start from the recorded bottleneck rather than reconstructing a build from raw logs.

Project first, environment second: use that evidence to improve dependency boundaries and action inputs, reuse compatible outputs, then choose capacity for the work that remains. Tuist supplies the evidence and supported reuse mechanisms; teams make the graph changes.

## What Bazel already does

[Bazel](https://bazel.build/) turns explicit targets and dependencies into actions such as compilation, linking, and test execution. It provides incremental builds, parallel scheduling, sandboxing, local action caching, and remote cache and execution protocols. Its Build Event Protocol records structured invocation events.

Remote caching reuses an action's existing outputs. Remote execution runs a cache-miss action on another machine. Bazel supports both concepts, but configuring one does not supply the other.

## How Tuist augments it

- **Reuse compatible action outputs across machines.** The [Bazel remote cache](/en/docs-markdown/guides/features/cache/bazel-cache) supplies the cache portion of the Remote Execution API. A matching action can download results produced elsewhere rather than execute again.
- **Investigate recorded build work.** [Build insights](/en/docs-markdown/guides/features/build-insights/bazel) collects build events and recorded profile data. Compare invocations, targets, cache behavior, and operations before changing execution capacity.
- **Correlate tests over time.** [Test insights](/en/docs-markdown/guides/features/test-insights/bazel) collects outcomes and individual cases from supported reports. Reporting works with normal `bazel test` after setup.
- **Apply explicit flaky-test policies.** The `tuist bazel test` wrapper retrieves and enforces documented quarantine policies. Muting and skipping have different boundaries; skipping a target also excludes its healthy sibling cases.

## First experiment

Follow the [Bazel getting-started guide](/en/docs-markdown/guides/get-started/bazel-project). Run `tuist init` and select the Bazel workspace. If your CLI does not offer that option, authenticate and run `tuist bazel setup`.

Commit `tuist.toml` and the generated `try-import %workspace%/.bazelrc.tuist` line in `.bazelrc`. Ignore `.bazelrc.tuist`: it contains a per-environment cache region and credential-helper path. Each machine needs its own setup.

```sh
bazel build //...
bazel test //...
```

Check build/test reports in Tuist and demonstrate remote reuse in a second compatible environment. Use the [flaky-test guide](/en/docs-markdown/guides/features/test-insights/flaky-tests/bazel) if you want quarantine applied through `tuist bazel test -- //...`. Follow provider-specific CI authentication, rather than copying a developer's local configuration.

## Open infrastructure you can improve

Tuist combines open-source tooling with public infrastructure code. Your team can [inspect the implementation](https://github.com/tuist/tuist), report issues, and [contribute improvements](https://github.com/tuist/tuist/blob/main/CONTRIBUTING.md) to the Bazel integration and shared infrastructure. Improve event processing, cache integration, or the developer experience with the maintainers rather than treating the implementation as a black box.

A closed hosted service leaves implementation changes entirely with the provider. Tuist gives your team a direct path to help improve the infrastructure it depends on. See [Openness](/marketing-markdown/openness) for the public components and their licenses.

## Sources and review

Written by Tuist. Sources reviewed on **2026-10-09**: [Bazel remote caching](https://bazel.build/remote/caching), [remote execution](https://bazel.build/remote/rbe), [Build Event Protocol](https://bazel.build/remote/bep), and the linked Tuist references. Compare the build system at bazel.build, not a remote-infrastructure vendor's offering.

[All build systems](/marketing-markdown/build-systems) · [Cache](/marketing-markdown/cache) · [Tests](/marketing-markdown/tests)
