# Tuist: my tests take too long

Tuist Test Insights, selective testing, and sharding help teams understand test time, avoid unnecessary execution, and balance work across machines. Start with Tuist test reporting, then enable the acceleration feature supported by your toolchain; moving CI jobs to Tuist Runners is not required.

## Diagnose the bottleneck

Measure the entire test job: test compilation, simulator or service startup, execution, retries, queueing, and result upload. Compare the same suite and configuration. Summing individual test durations is not the wall-clock duration when tests run concurrently.

| Symptom | What to investigate | Where Tuist helps |
| --- | --- | --- |
| A few tests dominate execution time | Slow cases, setup costs, and changes over time | [Test Insights](/en/docs-markdown/guides/features/test-insights) identifies reported slow tests. |
| Every change executes unchanged test targets | Modeled inputs and prior successful runs | [Selective testing](/en/docs-markdown/guides/features/selective-testing) skips unchanged test targets in Tuist-generated Xcode projects. |
| One parallel job finishes much later than others | Shard durations and test distribution | [Test sharding](/en/docs-markdown/guides/features/test-sharding) balances execution using recent timing history. |
| Retries dominate the job | Inconsistent outcomes and their cause | Investigate [flaky tests](/marketing-markdown/solutions/flaky-tests) instead of adding more shards. |
| Compilation dominates, not test execution | Repeated build outputs and misses | Use the matching [build cache](/marketing-markdown/cache). Caching compilation is not test-result selection. |

## Project first, environment second

Investigate slow fixtures, shared state, retries, and unnecessary execution before adding parallel capacity. Gradle and Elixir suites can then use supported Tuist sharding; Bazel has test insights but not Tuist sharding today. Improving the tests and distributing them are separate steps.

Selective testing operates at **test-target granularity**, using project-graph hashes and prior successful runs. It requires Tuist-generated Xcode projects and `tuist test`. It is not line-level test impact analysis and is not available for ordinary Xcode, Gradle, Bazel, or Elixir projects.

Sharding spreads the tests that execute across parallel CI machines. Tuist supports sharding for Xcode, Gradle, and Elixir; not Bazel today. It needs execution history and available parallel capacity. On generated projects, selective testing can skip unchanged targets and sharding can distribute the remainder.

If a suite has a few intrinsically slow tests, changing fixtures or test boundaries may be more effective than adding machines. Use evidence from [Tuist Tests](/marketing-markdown/tests) to choose the intervention rather than treating all parallelism as a saving.

## Investigate with an agent

An agent connected to the [Tuist MCP server](/en/docs-markdown/guides/features/agentic-coding/mcp) can use `list_test_cases` and `get_test_case` for duration history, then `list_test_case_runs` and `get_test_case_run` to examine individual attempts. Ask it to distinguish consistently slow tests from retry-driven time, and propose one measurable change.

The agent should check the toolchain support matrix before recommending selective testing or sharding. Reading metrics does not itself modify tests or configure CI. For a compilation-heavy job, follow the [slow-build investigation](/marketing-markdown/solutions/slow-builds) too.

## First experiment

1. Enable [test reporting](/en/docs-markdown/guides/features/test-insights) and establish typical wall-clock duration, retries, and total machine-minutes.
2. Investigate the slowest reported cases. If compilation dominates, test caching first.
3. On generated Xcode projects, evaluate selective testing. Where sharding is supported, try a small number of shards and inspect the longest shard.
4. Compare duration, coverage, queue time, and total machine-minutes. Keep the change only if it improves the goal you actually care about.

## Limitations

Missing results can distort timing history and balancing. Sharding needs multiple runners and may lower latency while increasing total compute usage through startup overhead and duplicated setup. Selective testing is only as complete as the modeled inputs; it is not a guarantee that arbitrary external effects are understood. Neither sharding nor quarantine fixes a slow or flaky test. Runners are optional; Tuist Runners remain invite-only with no public pricing.

Related: [flaky tests](/marketing-markdown/solutions/flaky-tests), [rising CI costs](/marketing-markdown/solutions/ci-costs), and [compare approaches](/marketing-markdown/compare).
