# Xcode test sharding: split iOS tests across parallel CI runners

Tuist shards Xcode tests across parallel CI runners: one job builds the tests once with `tuist xcodebuild build-for-testing`, the Tuist server splits the test modules or suites into balanced shards using the last 30 days of recorded timings, and each runner downloads the built test products and runs only its shard with `tuist xcodebuild test`. It works with ordinary Xcode projects and Tuist-generated projects, and the results from every shard come back together as one test run in test insights.

Improve the project first, then its execution environment. Sharding changes parallelism, not the amount of work: a suite that recompiles unchanged code or runs tests a change could not affect is still doing that work, just on more machines.

## Why one machine stops being enough

- **Parallel testing has a ceiling on one Mac.** `-parallel-testing-enabled` runs test classes on several simulator clones, but they share the machine's cores and memory, and simulator count is limited by both.
- **Long UI and integration suites set the floor.** One slow test module decides when the job ends, regardless of how fast everything else is.
- **Naive splits are unbalanced.** Splitting by target or alphabetically leaves one shard much longer than the rest, so the job waits for it.
- **Every shard rebuilding is waste.** Running `xcodebuild test` on each shard compiles the app and tests again on every machine.

## How Tuist addresses it

- **Build once, test many times.** The build phase uploads the `.xctestproducts` bundle, or writes an optimized shard archive for your CI's own artifact step, so shard runners only run tests.
- **Shards balanced by recorded time.** The server bin-packs modules, or test classes with `--shard-granularity suite`, using [Xcode test insights](/en/docs-markdown/guides/features/test-insights/xcode) timings, so shards finish at roughly the same time. With suite granularity the last shard is the catch-all, so new suites still run.
- **A matrix your CI already understands.** Tuist detects GitHub Actions, GitLab CI, CircleCI, Buildkite, Codemagic, and Bitrise and writes the shard matrix, child pipeline, or continuation parameters for each.
- **One result, not five.** Shard results are aggregated into one test run, with flaky-test detection and test history across shards.
- **Shards next to the cache.** On [Tuist Runners](/marketing-markdown/runners), each shard is a fresh M5 Pro Mac mini virtual machine on the same network as the [Xcode cache](/en/docs-markdown/guides/features/cache/xcode-cache) and test products. Adoption is one line: `runs-on: tuist-macos`. Runners are billed per minute of job time; the current rates are on the [pricing page](/pricing).

Setup, flags, and provider examples are in the [Xcode test sharding guide](/en/docs-markdown/guides/features/test-sharding/xcode), with a [separate guide for generated projects](/en/docs-markdown/guides/features/test-sharding/generated-xcode-project). Gradle projects use the [Gradle plugin's sharding](/marketing-markdown/solutions/gradle-test-sharding).

## Diagnose

Decide whether sharding is the right lever before adding machines:

| Question | Measure | Next step |
| --- | --- | --- |
| How long is the test step compared with the build? | Build duration in build insights and test run duration in test insights | If the build dominates, enable the Xcode cache before sharding |
| Is the time spread across modules or concentrated in one? | Test module and suite durations | One dominant module needs `suite` granularity or splitting the module |
| Do tests run that the change could not affect? | Test targets run per change | On generated projects, add [selective testing](/en/docs-markdown/guides/features/selective-testing) first |
| How much does each shard spend on setup? | Shard job duration minus test time | High setup cost means fewer, longer shards |
| Do retries make shards uneven? | Flaky tests and retried attempts | Fix or quarantine the worst flakes |

## Investigate with an agent

Through the authorized [Tuist MCP server](/en/docs-markdown/guides/features/agentic-coding/mcp), an agent can read the evidence for a shard count: `list_test_runs` and `get_test_run` for run duration and shard results, `list_test_module_runs` and `list_test_suite_runs` for where test time goes, `list_test_cases` with the flaky filter for tests that retry, `list_xcode_builds` for the build that precedes the tests, and `list_runner_jobs` for queue time and per-shard job duration on Tuist Runners. Ask the agent which module or suite sets the floor and how many shards the data supports; reading these records does not authorize changing workflows.

## First experiment

1. Configure [Xcode test insights](/en/docs-markdown/guides/features/test-insights/xcode) and record the slowest test workflow for a week so shards have timing data.
2. Replace the test step with `tuist xcodebuild build-for-testing --shard-total 2` and a matrix of `tuist xcodebuild test` jobs.
3. Compare the longest shard with the unsharded run in wall-clock time, and the sum of all shard jobs in total machine-minutes.
4. Try `--shard-granularity suite` if one module dominates, then raise the shard count only while the longest shard keeps getting shorter.

## Further reading

- [Speed up iOS CI](/marketing-markdown/solutions/speed-up-ios-ci): cache, test selection, sharding, flaky tests, and runners together.
- [Slow tests](/marketing-markdown/solutions/slow-tests) and [flaky tests](/marketing-markdown/solutions/flaky-tests).
- [Test sharding guide](/en/docs-markdown/guides/features/test-sharding), including shared volumes and shard archives.

## Frequently asked questions

### What is the difference between Xcode parallel testing and test sharding?

Xcode parallel testing runs test classes on several simulator clones on one machine, so it is limited by that machine's cores, memory, and simulators. Sharding splits the tests across several CI machines, each with its own simulators. They combine: each shard can still use parallel testing.

### Do I need a Tuist-generated project to shard Xcode tests?

No. `tuist xcodebuild build-for-testing` and `tuist xcodebuild test` wrap `xcodebuild` for ordinary Xcode projects and workspaces. Generated projects have their own sharding flow through `tuist test`, and can also use selective testing.

### How does Tuist decide which tests go in each shard?

The server uses the last 30 days of test timings from test insights and distributes test modules, or test classes with suite granularity, so each shard takes roughly the same time. Without recorded timings, shards are planned as if the suite were unknown, so configure test insights first.

### Does each shard have to rebuild the app?

No. The build phase builds once and uploads the test products, or writes a shard archive your CI transfers as an artifact, and each shard runs the tests from those products without compiling again.

### Does sharding make CI cheaper?

Not by itself. Each shard pays its own checkout, setup, and test-product download, so total machine-minutes can go up while wall-clock time goes down. The Xcode cache and selective testing reduce total work; sharding shortens the wait for what remains.

### How many shards should I use?

Start with two or three and add shards only while the longest shard keeps getting shorter. Once per-shard setup is a large part of each job, more shards add cost without making the run faster.
