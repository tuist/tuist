# Tuist: my CI costs are going up

Tuist helps teams investigate build and test work, reuse compatible outputs across CI, developer machines, and agents, and avoid unchanged test-target execution where supported. Start with the matching Tuist cache or test integration and measure avoided work before changing compute. Less work can reduce cost, but faster feedback is not automatically a smaller bill.

## Diagnose the increase

Compare equivalent periods and separate more activity from a more expensive job. Track job count, billed machine-minutes by shape, retry frequency, concurrency, and cache or artifact charges. Check included allowances and your actual contract, not just a provider's headline minute rate.

| Symptom | Measure | Tuist intervention to evaluate |
| --- | --- | --- |
| More CI runs and agent-created branches | Job count and compatible work repeated between environments | [Remote cache](/marketing-markdown/cache) so fresh environments can reuse trusted build outputs. |
| The same jobs take longer | Timed operations, cache misses, and configuration changes | [Build Insights](/en/docs-markdown/guides/features/build-insights), followed by a targeted graph, task, or cache change. |
| Reruns consume a growing share of compute | Failed attempts, retry frequency, and failure signatures | [Flaky-test investigation](/marketing-markdown/solutions/flaky-tests), with ownership and repair. |
| More shards lowered latency but raised usage | Total billed machine-minutes, repeated setup, and the longest shard | Rebalance [sharding](/marketing-markdown/solutions/slow-tests); avoid unchanged targets where selective testing is supported. |
| Larger machines cost more without proportional gains | Job duration multiplied by the actual shape rate | Right-size execution after identifying serial or non-compute bottlenecks. |
| Cache charges are growing | Requests, downloaded bytes, and time saved per workload | Compare the cost of reuse with rebuilding; use the live [pricing table](/pricing). |

## Project first, environment second

Improve task inputs, dependency boundaries, and costly retries before buying more execution capacity. For Gradle and Bazel, test compatible output reuse; for Elixir, investigate reported compilation and tests because Tuist has no remote build cache there. Keep Xcode-specific selection requirements separate from those integrations.

The [comparison billing table](/marketing-markdown/compare#billing-and-incentives) cites minute-, resource-, credit-, and build-based charges and their exceptions. Reducing work does not necessarily reduce a fixed subscription or per-build charge. Tuist also meters feature usage; include its charges rather than assuming all interests or savings automatically align.

## Evaluate total cost, not just runtime

For a representative workload, calculate:

```text
Total cost = billed compute + cache/download charges + artifact/storage charges
             + subscriptions + infrastructure operating costs
```

Apply allowances and negotiated rates to the relevant components. Track engineering maintenance effort separately if it cannot be priced reliably. Record wall-clock feedback time alongside cost rather than converting every minute saved into a promised cash saving.

Tuist Cache is independent of Tuist Runners. Clients normally receive a nearby regional endpoint, and compatible outputs can be reused by local developers and agent environments as well as CI. Enable the integration matching your build system and verify reuse from a second environment. A trusted CI producer with developer and agent readers can improve reuse without allowing every environment to upload artifacts.

[Selective testing](/en/docs-markdown/guides/features/selective-testing) can remove unchanged test-target execution, but only on Tuist-generated Xcode projects. [Sharding](/en/docs-markdown/guides/features/test-sharding) distributes execution and can increase total usage. Compare both against the same workload and coverage expectations.

## Investigate with an agent

Use the authorized [Tuist MCP server](/en/docs-markdown/guides/features/agentic-coding/mcp) to compare build operations, cache behavior, and test attempts. On Tuist Runners, `list_runner_jobs`, `list_runner_job_steps`, and `list_runner_job_metrics` add execution evidence. Give the agent your actual invoice rates and allowances separately; it should not infer prices or a complete bill from Tuist timing data.

Ask for the largest observed source of avoidable work, one intervention, and the evidence needed to validate it. Reading insights is not automatic cost optimization or authorization to resize machines.

## First experiment

1. Choose one high-volume workflow and establish its cost and timing baseline.
2. Reduce one source of duplicate work or retries using [Cache](/marketing-markdown/cache) or [Tests](/marketing-markdown/tests).
3. Rerun equivalent workloads and include the new cache and service charges.
4. Compare total cost and feedback time. If compute still dominates, review optional [Tuist Runners](/marketing-markdown/compute) against your required platforms and concurrency; access is invite-only and pricing is not public.

## Limitations

The bill may rise because the team ships more or runs more verification, even if each job improves. Caching can cost more than rebuilding small outputs. Quarantine can hide regressions; sharding is not inherently cheaper. Toolchain support and billing models differ, so use current [pricing guidance](/marketing-markdown/pricing). Tuist Runners are invite-only and have no public pricing; this page does not claim they are cheaper than another provider or guarantee savings.

Related: [slow builds](/marketing-markdown/solutions/slow-builds), [slow tests](/marketing-markdown/solutions/slow-tests), and [flaky tests](/marketing-markdown/solutions/flaky-tests).
