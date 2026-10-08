# Tuist: my builds are slow

Understand what the build is doing before buying more compute. Tuist combines toolchain-aware Build Insights with remote caching so developers, CI, and coding agents can investigate bottlenecks and reuse compatible outputs without moving jobs to Tuist Runners.

## Diagnose the bottleneck

Compare the same commit, toolchain version, build configuration, and machine shape. Record both a cold build and a repeat build. Separate queue time, dependency downloads, compilation, linking, packaging, and cache transfers; the longest operation is not necessarily the whole critical path because operations can overlap.

| Symptom | What to investigate | Where Tuist helps |
| --- | --- | --- |
| Every fresh checkout rebuilds unchanged code | Cacheable work, misses, compatible inputs, and download time | [Cache](/marketing-markdown/cache) shares build outputs across environments. |
| A small edit rebuilds much of the project | Dependency fan-out, target boundaries, build settings, and scripts | [Build Insights](/en/docs-markdown/guides/features/build-insights) provides recorded timings and toolchain data to ground a graph or configuration change. |
| A warm build is still slow | Slow files, tasks, transforms, linking, and serial work | Inspect timed operations before changing machine size or parallelism. |
| Swift package resolution dominates | Git checkout and dependency-resolution time | The [Swift package registry](/en/docs-markdown/guides/features/package-registries/swift) can replace Git-based retrieval for supported packages. |
| CI is slow but the same build is fast locally | Queueing, machine shape, cold state, and cache locality | [Compute](/marketing-markdown/compute) is an optional managed-runner choice, not a cache prerequisite. |

## Reduce work, then improve execution

Tuist records different evidence for different toolchains: Xcode build steps, targets, files, and cache tasks; Gradle task outcomes, configuration and transform timings; Bazel invocation metrics, profile intervals, and critical-path diagnostics; and Elixir compilation data. Start with the [Build Insights integration](/en/docs-markdown/guides/features/build-insights) matching the project.

Use that evidence to decide whether to split a highly connected module, correct an unnecessarily invalidated task, improve a script, or introduce caching. Insights do not automatically rewrite the build graph.

[Remote caching](/marketing-markdown/cache) reuses outputs keyed by compatible inputs. Tuist normally directs clients to a nearby regional endpoint. The cache serves developer machines and agent environments as well as CI; it does not require Tuist Runners. Configure trusted producers and verify that another environment can consume their outputs.

The integration matters: whole-module caching requires Tuist-generated Xcode projects; the Xcode compilation cache works with existing projects on Xcode 26 or later; Gradle and Bazel use their own build-cache integrations. Elixir has Build Insights but no Tuist remote build cache.

## Investigate with an agent

Connect the [Tuist MCP server](/en/docs-markdown/guides/features/agentic-coding/mcp) and give the agent a baseline build and a slow build. For Xcode, `list_xcode_build_steps` and `list_xcode_build_cache_tasks` expose timing and reuse evidence. For Gradle, use `list_gradle_build_tasks` and `list_gradle_build_steps`; for Bazel, use `get_bazel_invocation` and `list_bazel_build_steps`.

Ask for an evidence-backed bottleneck, one proposed change, and a before/after measurement. Missing or expired data is not proof that an operation was fast. Tool access requires authorization; Gradle and Bazel integrations need their own authentication in addition to MCP access. Review changes before applying them.

## First experiment

1. Connect [Build Insights](/en/docs-markdown/guides/features/build-insights) for the existing toolchain.
2. Measure a representative cold build and repeat build, including queue and transfer time.
3. Change one source of unnecessary work or enable the matching [cache integration](/marketing-markdown/cache).
4. Compare end-to-end duration and total compute consumption, not just hit rate. Repeat on a developer or agent machine as well as CI.

## Limitations

Caching helps only when compatible outputs exist and downloading them is worthwhile. A highly changed workload, serial linker bottleneck, or external service wait may need another intervention. A graph change can improve one build while making others worse; validate representative edits. Faster compute is sometimes the right answer, but no integration guarantees a speedup or lower costs. Tuist Runners are invite-only and their pricing is not public.

Related: [slow tests](/marketing-markdown/solutions/slow-tests), [rising CI costs](/marketing-markdown/solutions/ci-costs), and [compare approaches](/marketing-markdown/compare).
