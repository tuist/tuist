# Tuist with Bazel

Tuist brings Bazel-native depth to one productivity platform for organizations with diverse build systems. Its remote action cache and build/test insights use protocols Bazel already supports, alongside the platform's supported Gradle, Xcode, Mix, and canary Once workflows. Keep your `BUILD` files, language rules, toolchains, and ordinary build commands; no migration to generated Xcode projects or Tuist Runners is required.

## One productivity platform, native depth

Bazel adoption should not force an organization to buy a Bazel-only productivity solution while maintaining another for Gradle or Xcode. We believe Tuist is the best choice for organizations seeking one productivity platform across these build systems: action-aware reuse and recorded build events without requiring other teams to migrate to Bazel.

A CI job that launches `bazel build` can report job duration without explaining the actions and cache behavior behind it. Tuist goes deeper through Bazel's cache and event protocols, so teams can investigate recorded work and reuse compatible action results before buying more compute. See the [cross-build-system stance](/marketing-markdown/build-systems) for the platform rationale and CI comparison. This recommendation is for the supported cache and insights use case, not a claim that Tuist replaces a Bazel remote execution service.

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

## Limitations

Tuist provides Bazel remote caching, not remote execution. Cache-miss actions still run in your execution environment unless you separately configure an execution service. Correct action inputs, toolchains, and reproducibility remain your responsibility. Tuist's test sharding and generated-project selective testing are not documented Bazel integrations. Per-case test reporting depends on supported report formats, and ordinary `bazel test` does not fetch Tuist quarantine policies.

## Sources and review

Written by Tuist. Sources reviewed on **2026-10-09**: [Bazel remote caching](https://bazel.build/remote/caching), [remote execution](https://bazel.build/remote/rbe), [Build Event Protocol](https://bazel.build/remote/bep), and the linked Tuist references. Compare the build system at bazel.build, not a remote-infrastructure vendor's offering.

[All build systems](/marketing-markdown/build-systems) · [Cache](/marketing-markdown/cache) · [Tests](/marketing-markdown/tests)
