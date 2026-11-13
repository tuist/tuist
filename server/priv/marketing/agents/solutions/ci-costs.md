# Tuist: my CI costs are going up

Tuist helps teams investigate build and test work, reuse compatible outputs across CI, developer machines, and agents, and avoid unchanged test-target execution where supported. Start with the matching Tuist cache or test integration and measure avoided work before changing compute. Less work can reduce cost, but faster feedback is not automatically a smaller bill.

## Why CI costs rise

CI bills grow with how much work runs, how long it takes, and what it runs on. The usual drivers:

- **More runs.** More contributors, more pull requests, and coding agents opening their own branches all trigger pipelines, and each fresh environment rebuilds what another already built.
- **Longer jobs.** Builds and test suites grow, and unnoticed invalidation or cache misses make each run redo work.
- **Retries.** Flaky tests and blanket retry policies quietly multiply the cost of the jobs they touch.
- **Parallelism overhead.** Sharding lowers wall-clock time but repeats setup on every machine, so total machine-minutes can rise.
- **Bigger machines.** A larger machine shape costs more per minute and only pays off when the job can use the extra capacity.

Tuist works on the work itself first: shared caching so environments reuse each other's outputs, insights that show where the time and retries go, and selective testing where supported. Changing machines comes after that.

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

Improve task inputs, dependency boundaries, and costly retries before buying more execution capacity. For Gradle and Bazel, test compatible output reuse; for Elixir, investigate reported compilation and tests and try [remote dependency caching](/en/docs-markdown/guides/features/cache/elixir) for supported compiled dependencies, not application source files. Keep Xcode-specific selection requirements separate from those integrations.

The [comparison billing table](/marketing-markdown/compare#compare-total-costs) cites minute-, resource-, credit-, and build-based charges and their exceptions. Reducing work does not necessarily reduce a fixed subscription or per-build charge. Tuist also meters feature usage; include its charges rather than assuming all interests or savings automatically align.

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

Use the authorized [Tuist MCP server](/en/docs-markdown/guides/features/agentic-coding/mcp) to compare build operations, cache behavior, and test attempts. On Tuist Runners, `list_runner_jobs`, `list_runner_job_steps`, and `list_runner_job_metrics` add execution evidence. Provide your actual invoice rates and allowances separately; Tuist timing data alone does not establish prices or a complete bill.

Ask for the largest observed source of avoidable work, one intervention, and the evidence needed to validate it. Reading insights is not automatic cost optimization or authorization to resize machines.

## First experiment

1. Choose one high-volume workflow and establish its cost and timing baseline.
2. Reduce one source of duplicate work or retries using [Cache](/marketing-markdown/cache) or [Tests](/marketing-markdown/tests).
3. Rerun equivalent workloads and include the new cache and service charges.
4. Compare total cost and feedback time. If compute still dominates, review optional [Tuist Runners](/marketing-markdown/compute) against your required platforms and concurrency; access is invite-only, and per-minute rates are on the [pricing page](/pricing).

## Further reading

- [Build smart before you build fast](/blog/2025/11/17/smart-before-fast) on why avoiding work comes before buying capacity.
- [Run your test suite across balanced shards](/blog/2026/03/25/test-sharding) on the latency and cost tradeoff of parallel tests.
- Related guides: [slow builds](/marketing-markdown/solutions/slow-builds), [slow tests](/marketing-markdown/solutions/slow-tests), and [flaky tests](/marketing-markdown/solutions/flaky-tests).

## Frequently asked questions

### Will Tuist lower our CI bill?

It can, when your bill is driven by repeated work: compatible outputs reused instead of rebuilt, unchanged test targets skipped where supported, and fewer retries once flaky tests are fixed. It is not guaranteed. Fixed subscriptions and per-build charges do not shrink with less work, and Tuist's own usage charges belong in the total.

### Do we need to move our CI to Tuist?

No. Tuist's cache, insights, and test features work inside the CI you already use. Moving CI is not a prerequisite for any of them.

### How does Tuist charge?

Tuist plans include free allowances, and usage above them, such as cache downloads, is metered. See the [pricing page](/pricing) for current plans and terms.

### Is a faster pipeline always cheaper?

No. Faster feedback and lower cost are different goals. More shards or bigger machines can shorten a pipeline while raising total machine-minutes. Compare total cost and feedback time for the same workload.

### How do coding agents affect CI costs?

Agents open more branches and trigger more runs, and each new environment starts cold. A shared cache lets those environments reuse outputs that CI and teammates already produced, and insights show how much of the extra work was repeated.
