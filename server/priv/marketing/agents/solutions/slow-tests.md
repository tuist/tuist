# Tuist: my tests take too long

Tuist Test Insights, selective testing, and sharding help teams understand test time, avoid unnecessary execution, and balance work across machines. Start with Tuist test reporting, then enable the acceleration feature supported by your toolchain; moving CI jobs to Tuist Runners is not required.

## Why test suites get slow

Test time grows with the codebase, but rarely evenly. A suite usually gets slow for a few specific reasons:

- **Everything runs on every change.** Without a way to tell which tests a change can affect, CI runs the whole suite even when a commit touches one module.
- **A few tests dominate.** Expensive fixtures, real network or database calls, UI tests, and fixed waits often account for a large share of the time.
- **Work is spread unevenly.** Static splits across CI machines drift as tests are added, so one shard finishes long after the others and sets the pace.
- **Retries add hidden time.** Flaky tests that pass on a second attempt double their own cost and lengthen every job they appear in.
- **Compilation is counted as testing.** Building test targets can take longer than running them, and that is a build problem, not a test problem.

Tuist addresses these in order: [Test Insights](/en/docs-markdown/guides/features/test-insights) shows which tests and jobs take the time and how that changes over time, selective testing and the build cache avoid unnecessary work, and sharding balances what remains across machines.

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

Default selective testing operates at **test-target granularity**, using project-graph hashes and prior successful runs. It requires Tuist-generated Xcode projects and `tuist test`. An account-enabled early-access [coverage strategy](/en/docs-markdown/guides/features/selective-testing/generated-xcode-project) can additionally select individual XCTest/XCUITest tests, with coverage uploads and TestCoverageAttribution. Tuist selective testing is not available for ordinary Xcode, Gradle, Bazel, or Elixir projects.

Sharding spreads the tests that execute across parallel CI machines. Tuist supports sharding for Xcode, Gradle, and Elixir; not Bazel today. Cargo has target-level sharding within one package, and compatible Once releases support hosted shard plans; see the [sharding guides](/en/docs-markdown/guides/features/test-sharding) for their distinct requirements. Timing-balanced sharding uses reported execution history and needs parallel capacity. On generated projects, selective testing can skip unchanged targets and sharding can distribute the remainder. Measure total machine-minutes as well as wall-clock time: parallelism can increase setup and compute usage.

If a suite has a few intrinsically slow tests, changing fixtures or test boundaries may be more effective than adding machines. Use evidence from [Tuist Tests](/marketing-markdown/tests) to choose the intervention rather than treating all parallelism as a saving.

## Investigate with an agent

An agent connected to the [Tuist MCP server](/en/docs-markdown/guides/features/agentic-coding/mcp) can use `list_test_cases` and `get_test_case` for duration history, then `list_test_case_runs` and `get_test_case_run` to examine individual attempts. Ask it to distinguish consistently slow tests from retry-driven time, and propose one measurable change.

Check the toolchain support matrix before relying on selective testing or sharding. Reading metrics does not itself modify tests or configure CI. For a compilation-heavy job, follow the [slow-build investigation](/marketing-markdown/solutions/slow-builds) too.

## First experiment

1. Enable [test reporting](/en/docs-markdown/guides/features/test-insights) and establish typical wall-clock duration, retries, and total machine-minutes.
2. Investigate the slowest reported cases. If compilation dominates, test caching first.
3. On generated Xcode projects, evaluate selective testing. Where sharding is supported, try a small number of shards and inspect the longest shard.
4. Compare duration, coverage, queue time, and total machine-minutes. Keep the change only if it improves the goal you actually care about.

## Further reading

- [Run your test suite across balanced shards](/blog/2026/03/25/test-sharding) on timing-based sharding.
- [Stop flaky tests from blocking your PRs](/blog/2026/01/27/flaky-tests) on retries and quarantine.
- [Build smart before you build fast](/blog/2025/11/17/smart-before-fast) on avoiding work before adding capacity.
- Related guides: [flaky tests](/marketing-markdown/solutions/flaky-tests), [rising CI costs](/marketing-markdown/solutions/ci-costs), and [compare approaches](/marketing-markdown/compare).

## Frequently asked questions

### How do I find the slowest tests?

Enable [test reporting](/en/docs-markdown/guides/features/test-insights) for your build system. Tuist records each test case's duration across runs, so you can rank tests by time, see when a test became slower, and separate consistently slow tests from ones slowed by retries.

### Can Tuist run only the tests affected by a change?

Yes, with Tuist generated Xcode projects: selective testing runs only the test targets whose inputs changed since the last successful run. For other projects, a build cache can still avoid rebuilding unchanged code, but the tests themselves all run.

### Does sharding make CI cheaper?

Not necessarily. Sharding shortens wall-clock time by running tests on several machines at once, but each shard repeats setup work, so total machine-minutes can go up. Measure both before keeping a shard count.

### Which build systems does Tuist support for test acceleration?

Test insights support Xcode, Gradle, Bazel, and Elixir. Sharding supports Xcode, Gradle, and Elixir, but not Bazel today. Selective testing requires a Tuist generated Xcode project. Cargo and Once have their own requirements. See the [test sharding](/en/docs-markdown/guides/features/test-sharding) and [selective testing](/en/docs-markdown/guides/features/selective-testing) guides for each integration's requirements.

### Do we need to change CI providers?

No. Tuist works with the CI you already use, and test reporting, selective testing, and sharding run inside your existing jobs.
