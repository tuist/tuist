# Test sharding: split Xcode and Gradle tests across parallel CI runners

Tuist shards tests across parallel CI runners: a planning step asks the Tuist server for a shard plan balanced by the last 30 days of recorded test timings, your CI starts one job per shard, and each job runs only its shard's tests. Results from every shard come back together as one test run in test insights. Sharding works for Xcode projects, Tuist-generated projects, Gradle, and Elixir.

Sharding changes parallelism, not the amount of work. It shortens the wait for a long suite, but every shard pays its own checkout and setup, so total machine-minutes can go up. Caching and selective testing are what reduce total work; see [speed up iOS CI](/marketing-markdown/solutions/speed-up-ios-ci) and [speed up Gradle and Android CI](/marketing-markdown/solutions/speed-up-gradle-ci) for the order to apply them.

## When one machine stops being enough

- **Parallel testing on one machine has a ceiling.** Xcode's `-parallel-testing-enabled` and Gradle's `maxParallelForks` share one machine's cores and memory, and simulator count is limited by both.
- **One long module or suite sets the floor.** The job ends when its slowest part ends.
- **Naive splits are unbalanced.** Splitting by target, module, or class name leaves one shard much longer than the rest.

## How Tuist balances shards

- **Timings from test insights.** The server bin-packs test modules or suites by their recorded durations, so shards finish at roughly the same time. Configure test insights first; without history, shards are planned as if the suite were unknown.
- **New tests still run.** The last shard is a catch-all for suites with no recorded history.
- **A matrix your CI understands.** Tuist detects GitHub Actions, GitLab CI, CircleCI, Buildkite, Codemagic, and Bitrise and writes the shard matrix, child pipeline, or continuation parameters for each. Other providers read the shard matrix file.

## Xcode

One job builds the tests once with `tuist xcodebuild build-for-testing --shard-total <N>`, which uploads the `.xctestproducts` bundle or writes a shard archive for your CI's artifact step. Each shard job runs `tuist xcodebuild test` from those products without compiling again. `--shard-granularity suite` balances test classes instead of whole modules when one module dominates. It works with ordinary Xcode projects; generated projects use `tuist test --build-only` and can combine sharding with [selective testing](/en/docs-markdown/guides/features/selective-testing).

Setup: [Xcode test sharding](/en/docs-markdown/guides/features/test-sharding/xcode) and [generated projects](/en/docs-markdown/guides/features/test-sharding/generated-xcode-project).

## Gradle

The Tuist Gradle plugin's `tuistPrepareTestShards` task plans suites without compiling anything, so it can run on a small machine. Each shard job sets `TUIST_SHARD_INDEX` and runs the ordinary `test` task, which the plugin filters to that shard's suites. For Android projects, `-PtuistShardTestTask=testDebugUnitTest` plans only one variant's test task. With the [Gradle remote build cache](/en/docs-markdown/guides/features/cache/gradle-cache), shards download compiled outputs instead of each rebuilding them.

Setup: [Gradle test sharding](/en/docs-markdown/guides/features/test-sharding/gradle). Elixir has its own [sharding guide](/en/docs-markdown/guides/features/test-sharding/elixir).

## First experiment

1. Configure test insights and record the slowest test workflow for a week so shards have timing data.
2. Shard it into two or three shards.
3. Compare the longest shard with the unsharded run in wall-clock time, and the sum of all shard jobs in total machine-minutes.
4. Add shards only while the longest shard keeps getting shorter.

Shards run on any runner. On [Tuist Runners](/marketing-markdown/runners), each shard is a fresh machine on the same network as the cache and test products: `runs-on: tuist-macos` or `runs-on: tuist-linux`, billed per minute of job time at the rates on the [pricing page](/pricing).

## Frequently asked questions

### What is the difference between parallel testing and test sharding?

Xcode parallel testing and Gradle's `maxParallelForks` run tests concurrently on one machine, so they are limited by its cores, memory, and simulators. Sharding splits the tests across several CI machines. They combine: each shard can still test in parallel.

### How does Tuist decide which tests go in each shard?

The server uses the last 30 days of timings from test insights and distributes test modules or suites so each shard takes roughly the same time. The last shard also runs suites that have no recorded history, such as newly added ones.

### Does each shard have to rebuild the app?

Not for Xcode: the build phase builds once and each shard runs from the uploaded test products. Gradle shards run the test task themselves, so a shared remote build cache is what keeps them from recompiling.

### Does test sharding make CI cheaper?

Not by itself. Each shard pays its own checkout, setup, and download, so total machine-minutes can go up while wall-clock time goes down. A shared cache and selective testing reduce total work; sharding shortens the wait for what remains.

### How many shards should I use?

Start with two or three and add shards only while the longest shard keeps getting shorter. Once per-shard setup is a large part of each job, more shards add cost without making the run faster.
