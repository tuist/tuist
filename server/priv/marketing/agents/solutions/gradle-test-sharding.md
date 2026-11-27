# Gradle test sharding: split Android and JVM tests across parallel CI runners

Tuist shards Gradle tests across parallel CI runners: the Tuist Gradle plugin's `tuistPrepareTestShards` task plans test suites into balanced shards from the last 30 days of recorded timings without compiling anything, and each runner sets `TUIST_SHARD_INDEX` and runs the ordinary `test` task, which the plugin filters to that shard's suites. The last shard also runs every suite with no recorded history, so new tests are never dropped, and results from every shard come back together in test insights.

Improve the project first, then its execution environment. Sharding changes parallelism, not the amount of work: tasks that rerun on unchanged inputs still rerun on every shard unless a shared build cache lets the shards reuse them.

## Why one machine stops being enough

- **`maxParallelForks` has a ceiling.** Forking test JVMs parallelizes tests on one machine, but they share its cores and memory.
- **Android variants multiply test tasks.** Every build variant has its own unit test task, and a large multi-module project runs hundreds of them.
- **Naive splits are unbalanced.** Splitting by module or by test class name leaves one shard much longer than the rest, so the job waits for it.
- **Every shard pays setup.** Each runner checks out, configures Gradle, and compiles before running tests, so more shards are not free.

## How Tuist addresses it

- **Planning without compiling.** The build phase finds the projects that have the test task to shard and asks the server for a plan, so it is fast and can run on a small machine.
- **Shards balanced by recorded time.** The server bin-packs test suites by their [Gradle test insights](/en/docs-markdown/guides/features/test-insights/gradle) timings, so shards finish at roughly the same time. On the first run, with no history, the plan is one shard that runs everything.
- **The test task you already run.** Shards run `./gradlew test`, or the variant task such as `testDebugUnitTest` selected with `-PtuistShardTestTask`; test tasks in projects with no suites in a shard are skipped.
- **A matrix your CI already understands.** Tuist detects GitHub Actions, GitLab CI, CircleCI, Buildkite, Codemagic, and Bitrise and writes the shard matrix, child pipeline, or continuation parameters for each.
- **Shards that reuse compiled outputs.** With the [Gradle remote build cache](/en/docs-markdown/guides/features/cache/gradle-cache), each shard downloads the compilation and resource tasks another job already ran instead of repeating them. On [Tuist Runners](/marketing-markdown/runners), shards run on Linux machines on the same network as that cache, with `/dev/kvm` for Android emulators. Adoption is one line: `runs-on: tuist-linux`. Runners are billed per minute of job time; the current rates are on the [pricing page](/pricing).

Setup, properties, and provider examples are in the [Gradle test sharding guide](/en/docs-markdown/guides/features/test-sharding/gradle). Xcode projects use [Xcode test sharding](/marketing-markdown/solutions/xcode-test-sharding).

## Diagnose

Decide whether sharding is the right lever before adding machines:

| Question | Measure | Next step |
| --- | --- | --- |
| How long are tests compared with compilation? | Per-task timings in [Gradle build insights](/en/docs-markdown/guides/features/build-insights/gradle) and test run duration in test insights | If compilation dominates, enable the remote build cache before sharding |
| Is the time spread across suites or concentrated in one? | Test suite durations | One dominant suite needs splitting in code, because sharding balances whole suites |
| How much does each shard spend before tests start? | Shard job duration minus test time | High setup cost means fewer, longer shards and a better cache hit rate |
| Do retries make shards uneven? | Flaky tests and retried attempts | Fix or quarantine the worst flakes |

## Investigate with an agent

Through the authorized [Tuist MCP server](/en/docs-markdown/guides/features/agentic-coding/mcp), an agent can read the evidence for a shard count: `list_test_runs` and `get_test_run` for run duration and shard results, `list_test_suite_runs` for where test time goes, `list_test_cases` with the flaky filter for tests that retry, `list_gradle_builds` and `list_gradle_build_tasks` for compilation that runs before tests instead of coming from the cache, and `list_runner_jobs` for queue time and per-shard job duration on Tuist Runners. Ask the agent which suite sets the floor and how many shards the data supports; reading these records does not authorize changing build scripts or workflows.

## First experiment

1. Configure [Gradle test insights](/en/docs-markdown/guides/features/test-insights/gradle) and the remote build cache, and record the slowest test workflow for a week so shards have timing data.
2. Add a job that runs `./gradlew tuistPrepareTestShards -PtuistShardMax=2` and a matrix of shard jobs with `TUIST_SHARD_INDEX` set.
3. Compare the longest shard with the unsharded run in wall-clock time, and the sum of all shard jobs in total machine-minutes.
4. Raise `tuistShardMax` only while the longest shard keeps getting shorter.

## Further reading

- [Speed up Gradle and Android CI](/marketing-markdown/solutions/speed-up-gradle-ci): build cache, sharding, flaky tests, and runners together.
- [Slow tests](/marketing-markdown/solutions/slow-tests) and [flaky tests](/marketing-markdown/solutions/flaky-tests).
- [Test sharding guide](/en/docs-markdown/guides/features/test-sharding) for Xcode, generated projects, Gradle, and other toolchains.

## Frequently asked questions

### What is the difference between maxParallelForks and test sharding?

`maxParallelForks` runs several test JVMs on one machine, so it is limited by that machine's cores and memory. Sharding splits the test suites across several CI machines. They combine: each shard can still fork several JVMs.

### How does Tuist decide which tests go in each shard?

The server uses the test suites and timings that test insights recorded for your projects in the last 30 days and distributes the suites so each shard takes roughly the same time. The last shard also runs every suite that is not assigned to another shard, such as newly added ones.

### Can I shard only one Android build variant?

Yes. Pass `-PtuistShardTestTask=testDebugUnitTest`, or another variant's test task, to `tuistPrepareTestShards` so only the projects that have that task are planned, and run the same task in each shard.

### Does sharding make Gradle CI cheaper?

Not by itself. Each shard pays its own checkout, Gradle configuration, and compilation, so total machine-minutes can go up while wall-clock time goes down. A shared build cache reduces that repeated compilation; sharding shortens the wait for the tests that remain.

### Which CI providers does Gradle test sharding support?

Tuist detects GitHub Actions, GitLab CI, CircleCI, Buildkite, Codemagic, and Bitrise and writes the matching shard configuration. Other providers can read the shard matrix file and start one job per shard.
