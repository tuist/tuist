# Speed up Gradle and Android CI: remote build cache, test sharding, flaky tests, and runners

Tuist speeds up Gradle and Android CI by removing repeated work first and then running what remains on faster machines: a Gradle remote build cache shared by CI and developers, timing-balanced test sharding, flaky-test detection and quarantine, and managed Linux runners with hardware-accelerated Android emulators next to the cache. Each step works with the CI provider you already use, and each one is measured in the same build and test insights.

Improve the project first, then its execution environment. A larger machine makes every minute cheaper, but a job that reruns tasks whose inputs did not change and repeats a whole test suite on one machine still spends most of those minutes repeating work.

## Why Gradle CI gets slow

- **Every job starts cold.** An ephemeral CI machine has no local build cache, so it reruns compilation, annotation processing, and resource tasks that another job or a developer already ran on the same inputs.
- **The build cache is off.** Gradle only reuses task outputs when `org.gradle.caching=true` is set; without it, even a configured remote cache is never read or written.
- **Cache misses hide in task inputs.** Absolute paths, timestamps, and non-deterministic generated files change a task's cache key, so the cache exists but rarely hits.
- **One machine runs every test task.** `maxParallelForks` parallelizes tests on one machine; a long unit test suite or instrumented tests on emulators still set the floor for the job.
- **Flaky tests add retries.** A test that fails intermittently turns into reruns with the test-retry plugin, blocked merges, and extra minutes.
- **Emulators need virtualization.** Instrumented tests and Gradle Managed Devices are slow or impossible on Linux machines without hardware-accelerated virtualization.

## The levers, in order

| Step | What it removes | Tuist feature | Requirements |
| --- | --- | --- | --- |
| 1. Measure | Guessing | [Gradle build insights](/en/docs-markdown/guides/features/build-insights/gradle) and [test insights](/en/docs-markdown/guides/features/test-insights/gradle) | Tuist Gradle plugin |
| 2. Share task outputs | Rerunning unchanged tasks on cold machines | [Gradle remote build cache](/en/docs-markdown/guides/features/cache/gradle-cache) | Tuist Gradle plugin and `org.gradle.caching=true` |
| 3. Split the tests | Wall-clock time of one long test task | [Test sharding](/marketing-markdown/solutions/test-sharding) | Gradle test insights for timing-balanced shards |
| 4. Contain flaky tests | Retries and blocked merges | [Flaky-test detection and quarantine](/marketing-markdown/solutions/flaky-tests) | Gradle test insights; mute or skip quarantine through the plugin |
| 5. Run on faster machines | Time spent on small, shared hardware and software emulation | [Tuist Runners](/marketing-markdown/runners) | GitHub Actions organization, GitLab CI, Buildkite, or Bitrise |

Tuist does not offer selective testing for Gradle today: every shard and every run executes the tests assigned to it. Sharding spreads the work across machines and can increase total machine-minutes because each shard pays its own setup; the build cache is what reduces total work.

## How Tuist addresses it

- **One cache for developers, CI, and agents.** The [Tuist Gradle plugin](/en/docs-markdown/guides/install-gradle-plugin) connects Gradle's built-in build cache to a shared server, so CI reuses task outputs that a developer or an earlier job already produced. A common setup pushes from CI and keeps developer machines read-only.
- **Cache behavior you can see.** Build insights record each task's duration and whether it came from the cache, so a low hit rate points at the task whose inputs differ between machines instead of at the cache as a whole.
- **Tests split by recorded time.** Sharding plans test suites across shards from the last 30 days of recorded timings without compiling anything in the planning step, so each shard finishes at roughly the same time.
- **Reliability as part of speed.** Flaky-test detection works with the [Test Retry plugin](https://github.com/gradle/test-retry-gradle-plugin) and across runs, and quarantine either mutes a known flake or skips it on CI so it stops blocking merges while someone fixes it.
- **Faster Linux machines next to the cache.** [Tuist Runners](/marketing-markdown/runners) run Ubuntu with Docker and the Android SDK preinstalled, `/dev/kvm` for [hardware-accelerated Android emulators](/en/docs-markdown/guides/features/runners#android-emulators), and the cache on the same private network. Adoption is one line: `runs-on: tuist-linux`. Runners are billed per minute of job time; the current rates are on the [pricing page](/pricing).

The same approach applies to Xcode and Bazel: see [speed up iOS CI](/marketing-markdown/solutions/speed-up-ios-ci) and [Bazel on GitHub Actions](/marketing-markdown/solutions/bazel-github-actions). Feature support differs by toolchain, so check each guide.

## Diagnose

Start from one slow workflow and split its time before changing anything:

| Question | Measure | Next step |
| --- | --- | --- |
| How much of the job is task execution, and which tasks? | Build duration and per-task timings in build insights | If the same tasks run on every job, enable the remote build cache |
| Do tasks rerun when nobody changed their inputs? | Cache hits and misses per task | Low hit rates point to inputs that differ between machines, such as absolute paths, timestamps, or generated files |
| How long do tests take, and which ones? | Test run duration and slowest test cases in test insights | Shard the longest test task |
| How many runs need a retry? | Flaky tests and retried attempts | Fix or quarantine the tests that fail most often |
| Is the job waiting for or limited by the machine? | Queue time and CPU and memory per job on [Tuist Runners](/en/docs-markdown/guides/features/runners) | A larger machine shape or more concurrency |

## Investigate with an agent

Through the authorized [Tuist MCP server](/en/docs-markdown/guides/features/agentic-coding/mcp), an agent can read where a job spends time: `list_gradle_builds` and `get_gradle_build` for build duration and cache results, `list_gradle_build_tasks` for the tasks that ran instead of coming from the cache, `list_test_runs` and `get_test_run` for test duration, `list_test_cases` with the flaky filter for unreliable tests, and `list_runner_jobs` for queue and job evidence on Tuist Runners. Ask the agent for the largest repeated cost and the evidence for one change; reading these records does not authorize changing build scripts, workflows, or quarantine state.

## First experiment

1. Install the Tuist Gradle plugin, set `org.gradle.caching=true`, and record the slowest pull-request workflow's duration, cache hits, and test time for a week.
2. Push to the cache from CI only and compare the same workflow on the same machines; fix the tasks with the most misses first.
3. Shard the longest test task into two or three shards with `tuistPrepareTestShards` and compare the longest shard with the unsharded run, in both wall-clock time and total machine-minutes.
4. Point a copy of the job, or the emulator job, at `tuist-linux` and compare duration, queue time, and cost per job.

## Further reading

- [Gradle build cache guide](/en/docs-markdown/guides/features/cache/gradle-cache), including the cache upload policy and disabling the local cache on CI.
- [Test sharding](/marketing-markdown/solutions/test-sharding) and [flaky tests](/marketing-markdown/solutions/flaky-tests).
- [Slow builds](/marketing-markdown/solutions/slow-builds), [slow tests](/marketing-markdown/solutions/slow-tests), and [rising CI costs](/marketing-markdown/solutions/ci-costs).

## Frequently asked questions

### What is the fastest way to speed up Gradle builds on CI?

Turn on Gradle's build cache with a remote cache that every CI job shares. Ephemeral runners start empty, so without a remote cache they rerun every task; with one, tasks whose inputs did not change are downloaded instead of executed. Then check per-task cache misses, because one non-deterministic input can disable caching for everything downstream.

### Is caching ~/.gradle with actions/cache the same as a remote build cache?

No. Restoring `~/.gradle` from a CI cache saves dependency downloads and can carry a local build cache between runs of one branch, but it is large, keyed by the whole directory, and slow to upload and download. A remote build cache stores individual task outputs keyed by their inputs, so jobs on any branch and developers' machines reuse the same results.

### How do I run Android emulator tests on CI faster?

Run them on Linux machines with hardware-accelerated virtualization, because software emulation is slow and unreliable. Tuist Linux runners expose `/dev/kvm` on every profile, so x86_64 emulators and Gradle Managed Devices run without a separate KVM setup, on the same network as the build cache that skips the compilation before them.
