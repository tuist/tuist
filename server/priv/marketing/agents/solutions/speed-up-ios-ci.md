# Speed up iOS CI: cache, test selection, sharding, flaky tests, and runners

Tuist speeds up iOS and macOS CI by removing repeated work first and then running what remains on faster machines: a shared Xcode compilation cache, selective testing and test sharding, flaky-test quarantine, and managed Apple silicon runners next to the cache. Each step works with the CI provider you already use, and each one is measured in the same build and test insights.

Improve the project first, then its execution environment. A faster Mac makes every minute cheaper, but a job that recompiles unchanged code and reruns unchanged tests still spends most of those minutes repeating work.

## Why iOS CI gets slow

- **Every job starts cold.** A fresh CI machine has no DerivedData, so it compiles every module that a teammate's machine or the previous job already compiled.
- **Every change runs every test.** Without test selection, a one-line change in one feature runs the whole suite, including test targets whose inputs did not change.
- **One machine runs the whole suite.** A long suite on a single simulator sets the floor for the job's wall-clock time.
- **Flaky tests add retries.** A test that fails intermittently turns into reruns, blocked merges, and extra macOS minutes.
- **Hosted macOS runners are small.** GitHub's standard macOS runner has three M1 cores and 7 GB of memory, so compilation and simulators compete for resources.

## The levers, in order

| Step | What it removes | Tuist feature | Requirements |
| --- | --- | --- | --- |
| 1. Measure | Guessing | [Build insights](/en/docs-markdown/guides/features/build-insights) and [test insights](/en/docs-markdown/guides/features/test-insights) | Any Xcode project |
| 2. Share compilation outputs | Recompiling unchanged code on cold machines | [Xcode cache](/en/docs-markdown/guides/features/cache/xcode-cache) | Xcode 26 or later; works with ordinary Xcode projects |
| 3. Replace whole modules with binaries | Building unchanged modules at all | [Module cache](/en/docs-markdown/guides/features/cache/module-cache) | Tuist-generated projects |
| 4. Run only affected tests | Running unchanged test targets | [Selective testing](/en/docs-markdown/guides/features/selective-testing) | Tuist-generated projects and `tuist test` |
| 5. Split the remaining tests | Wall-clock time of one long suite | [Xcode test sharding](/marketing-markdown/solutions/xcode-test-sharding) | Xcode test insights for timing-balanced shards |
| 6. Contain flaky tests | Retries and blocked merges | [Flaky-test detection and quarantine](/marketing-markdown/solutions/flaky-tests) | Test insights; quarantine through the Tuist test wrapper |
| 7. Run on faster machines | Time spent on small, shared hardware | [Tuist Runners](/marketing-markdown/runners/github-actions) | GitHub Actions organization, GitLab CI, Buildkite, or Bitrise |

The Xcode cache and the module cache work at different granularity, whole-module substitution and compilation-output reuse, and they combine. Selective testing reduces total work; sharding spreads the remaining work across machines and can increase total machine-minutes because each shard pays its own setup.

## How Tuist addresses it

- **One cache for developers, CI, and agents.** The [Tuist cache](/marketing-markdown/cache) shares Xcode compilation outputs across machines, so a CI job reuses what a developer or an earlier job already compiled. It works on any runner, including GitHub-hosted runners and your own Mac minis.
- **Tests that match the change.** On generated projects, selective testing skips test targets whose inputs did not change since the last successful run, and sharding balances the rest using recorded timings.
- **Reliability as part of speed.** Flaky-test detection records every attempt, so retries become evidence instead of hidden minutes, and quarantine stops a known flake from blocking merges while someone fixes it.
- **Faster hardware next to the cache.** [Tuist Runners](/marketing-markdown/runners) are managed M5 Pro Mac minis with a fresh virtual machine per job, one Xcode per image, and the cache on the same private network. Adoption is one line: `runs-on: tuist-macos`. Runners are billed per minute of job time; the current rates are on the [pricing page](/pricing).

The same approach applies to Gradle, Bazel, and Elixir: [Gradle](/en/docs-markdown/guides/features/cache/gradle-cache) and [Bazel](/en/docs-markdown/guides/features/cache/bazel-cache) remote caches, Gradle and Elixir test sharding, and flaky-test detection for all of them; the [Gradle and Android CI guide](/marketing-markdown/solutions/speed-up-gradle-ci) walks through the Gradle path. Feature support differs by toolchain, so check each guide.

## Diagnose

Start from one slow workflow and split its time before changing anything:

| Question | Measure | Next step |
| --- | --- | --- |
| How much of the job is compilation? | Build duration and per-target compilation time in build insights | If most targets compile on every run, enable the Xcode cache |
| Do jobs recompile code nobody changed? | Cache hits and misses per build | Low hit rates point to inputs that differ between machines, such as paths or build settings |
| How long do tests take, and which ones? | Test run duration and slowest test cases in test insights | Selective testing on generated projects, then sharding for the remainder |
| How many runs need a retry? | Flaky tests and retried attempts | Fix or quarantine the tests that fail most often |
| Is the job waiting for or limited by the machine? | Queue time and CPU and memory per job on [Tuist Runners](/en/docs-markdown/guides/features/runners) | A larger machine shape or more concurrency |

## Investigate with an agent

Through the authorized [Tuist MCP server](/en/docs-markdown/guides/features/agentic-coding/mcp), an agent can read where a job spends time: `list_xcode_builds` and `list_xcode_build_targets` for compilation, `list_test_runs` and `get_test_run` for test duration and selective-testing results, `list_test_cases` with the flaky filter for unreliable tests, and `list_runner_jobs` for queue and job evidence on Tuist Runners. `get_xcode_build` and `get_test_run` can also return suggestions for Tuist capabilities the project isn't using yet, such as the Xcode compilation cache or test sharding. Ask the agent for the largest repeated cost and the evidence for one change; reading these records does not authorize changing workflows or quarantine state.

## First experiment

1. Pick the slowest pull-request workflow and record its duration, cache results, and test time for a week with build and test insights.
2. Enable the [Xcode cache](/en/docs-markdown/guides/features/cache/xcode-cache) and compare the same workflow on the same machines.
3. Shard the test step into two or three shards and compare the longest shard with the unsharded run, in both wall-clock time and total machine-minutes.
4. Point a copy of the job at `tuist-macos` and compare duration, queue time, and cost per job.

## Further reading

- [Slow builds](/marketing-markdown/solutions/slow-builds), [slow tests](/marketing-markdown/solutions/slow-tests), and [flaky tests](/marketing-markdown/solutions/flaky-tests).
- [Rising CI costs](/marketing-markdown/solutions/ci-costs) and [self-hosted Mac runners](/marketing-markdown/solutions/self-hosted-mac-runners).
- [Tuist Runners for GitHub Actions](/marketing-markdown/runners/github-actions), including macOS runner rates compared with GitHub-hosted runners.

## Frequently asked questions

### What is the fastest way to speed up iOS CI?

Stop repeating work. On Xcode 26 or later, a shared compilation cache lets CI reuse what other machines already compiled, which usually removes more time than a faster machine. Then reduce and split tests, and only then move the remaining work to faster runners.

### Does caching DerivedData on CI help?

Restoring DerivedData from a CI cache helps a single branch, but it is large, tied to absolute paths, and slow to upload and download. The Xcode compilation cache shares individual compilation outputs keyed by their inputs, so jobs on any branch and developers' machines reuse the same results.

### Can I run only the tests affected by a change in my Xcode project?

Yes, with Tuist-generated Xcode projects: selective testing skips test targets whose inputs did not change since the last successful run. Ordinary Xcode projects can still use the Xcode cache, test sharding, and flaky-test detection.

### Does test sharding make CI cheaper?

Not by itself. Sharding shortens wall-clock time by running tests in parallel, but each shard pays its own checkout and setup, so total machine-minutes can go up. Selective testing and caching reduce total work.

### Do I need to change CI providers?

No. The cache, insights, selective testing, sharding, and flaky-test detection work with your current CI. Tuist Runners plug into GitHub Actions, GitLab CI, Buildkite, and Bitrise when you want faster macOS machines.
