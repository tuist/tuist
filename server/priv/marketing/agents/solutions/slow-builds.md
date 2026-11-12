# Slow builds: find the work worth removing · Tuist

Tuist helps engineering teams and coding agents investigate slow builds and reuse compatible outputs without replacing CI. Improve the project first, then its execution environment: start with recorded build evidence and remove unnecessary work before buying more compute.

Tuist is build infrastructure for engineering teams and coding agents. It provides build evidence and capabilities, not a coding agent or automatic project repair.

## Choose an approach

| Approach | Good fit | Tradeoff |
| --- | --- | --- |
| Tuist | Shared build evidence and compatible-output reuse across environments. | Requires integration and a measured experiment, not a promised speedup. |
| CI | Triggering and orchestrating build jobs. | Keep it; orchestration does not remove expensive project work. |
| Optimization suite | A focused tool already addresses the measured bottleneck. | Compare evidence, supported actions, and total operating cost. |
| Do nothing | Build time is acceptable and waiting is infrequent. | Reassess if lost feedback time grows; avoid integration for its own sake. |

## Diagnose

Compare the same commit, toolchain, configuration, and machine shape. Record cold and repeat builds. Separate queue time, dependency retrieval, compilation, linking, packaging, and cache transfers. Operations overlap, so the longest operation alone is not necessarily the critical path.

| Symptom | First investigation | Existing reference |
| --- | --- | --- |
| Fresh environments rebuild unchanged code | Compatible inputs, cache misses, and transfer cost. | [Cache integration guide](/en/docs-markdown/guides/features/cache) |
| Small edits rebuild much of the project | Dependency fan-out, task inputs, settings, and scripts. | [Build Insights](/en/docs-markdown/guides/features/build-insights) |
| Warm builds remain slow | Timed operations and serial work before buying capacity. | [Build Insights](/en/docs-markdown/guides/features/build-insights) |
| Only CI is slow | Queueing, cold state, machine capacity, and cache locality. | [Compute requirements](/en/docs-markdown/guides/features/runners) |

Start with the supported integration for the existing project. Cache requirements differ: whole-module substitution and compilation-output reuse are separate capabilities. The linked guides are setup and measurement references, not evidence of a universal speedup. Insights do not automatically rewrite the build graph.

## Investigate with an agent

Connect the [Tuist MCP server](/en/docs-markdown/guides/features/agentic-coding/mcp) and give your coding agent a baseline and slow build. For example, `list_xcode_build_steps` and `list_xcode_build_cache_tasks` expose recorded timing and reuse evidence for their supported integration. Check the MCP guide for tools matching the project and any separate integration authentication.

Ask for an evidence-backed bottleneck, one proposed change, and a before/after measurement. Missing data is not proof an operation was fast. Reading evidence does not authorize writes: review proposed changes before applying them.

## First experiment

1. Connect [Build Insights](/en/docs-markdown/guides/features/build-insights) for one project.
2. Record representative cold and repeat builds, including queue and transfer time.
3. Remove one source of unnecessary work or enable the matching [cache integration](/marketing-markdown/cache).
4. Compare end-to-end duration and total machine usage, not only hit rate. Repeat in development or an agent environment as well as CI.

## Questions before you start

### What is Tuist?

Tuist is build infrastructure for engineering teams and coding agents. For slow builds, start with evidence and reuse rather than a CI migration.

### Does this replace CI?

No. Existing CI keeps orchestrating jobs. Cache and insights work independently of the optional managed Compute service.

### Can we adopt it incrementally?

Yes. Instrument one project, establish a baseline, and test one intervention before expanding. Check each feature's integration requirements instead of assuming all projects have the same capabilities.

### Hosted or self-hosted?

Use hosted Tuist, or operate a [self-hosted server](/en/docs-markdown/guides/server/self-host/server) and [cache nodes](/en/docs-markdown/guides/features/cache/self-hosting). Self-hosting brings operational responsibility and does not grant access to the invite-only managed Compute fleet.

### How do we measure value?

Measure feedback time and total machine usage before and after a representative change. Include transfer overhead, integration and operational effort, and current [Tuist pricing](/pricing). Do not treat hit rate or a faster isolated task as proof of end-to-end savings.

Related: [slow tests](/marketing-markdown/solutions/slow-tests) and [rising CI costs](/marketing-markdown/solutions/ci-costs).
