# Tuist Cache: reuse compatible build outputs

For engineering teams and coding agents repeating the same build work, Tuist Cache shares compatible outputs across development and CI without moving jobs. A cache hit reuses an output; a miss builds normally. It does not repair an inefficient build graph.

Tuist is build infrastructure for engineering teams and coding agents: a coding environment where people build. Cache is part of that infrastructure, not a replacement for CI or a coding agent. Improve the project first, then its execution environment: remove unnecessary work and reuse what remains.

## Choose an approach

| Approach | Good fit | Tradeoff |
| --- | --- | --- |
| Tuist Cache | Repeated compatible work across machines and agents. | Reuse depends on matching inputs and transfer cost. |
| CI | Triggering and orchestrating jobs. | Keep it; compare existing cache capabilities before adding more. |
| Optimization suite | A focused tool already addresses the bottleneck. | Compare integration depth, reuse scope, and operating cost. |
| Do nothing | Incremental builds are fast and repeated work is rare. | Remote transfer can cost more time than compilation saves. |

## Start with one project

Follow the [cache integration guide](/en/docs-markdown/guides/features/cache) for the existing project. Compilation caching and whole-module caching are separate integrations with different prerequisites; choose the matching guide rather than assuming parity. Configure authentication and trusted producers, build once, then verify reuse from another environment with matching inputs.

Use [Build Insights](/en/docs-markdown/guides/features/build-insights) and the cache dashboards to inspect reported hits, misses, and transfers. These are integration references and measurements, not a guarantee of savings for a new project.

## Questions before you start

### What is Tuist?

Tuist is build infrastructure for engineering teams and coding agents: a coding environment where people build. Cache shares compatible build outputs within that environment.

### Does this replace CI?

No. Keep CI orchestration and existing machines. [Compute](/marketing-markdown/compute) is optional and is not required to use Cache.

### Can we adopt it incrementally?

Yes. Start with one supported integration and compare representative cold and repeat builds before expanding. Requirements and reuse scope differ by integration.

### Hosted or self-hosted?

Use hosted cache, or deploy [self-hosted cache nodes](/en/docs-markdown/guides/features/cache/self-hosting) connected to hosted or self-hosted Tuist. Operating your own nodes includes storage, routing, and upgrades.

### How do we measure value?

Compare end-to-end duration for the same inputs, cache hits, and lookup/transfer overhead. Include operating effort and the account's current Tuist usage charges from [pricing](/pricing). A high hit rate alone does not prove faster or cheaper builds.

Related: [diagnose slow builds](/marketing-markdown/solutions/slow-builds).
