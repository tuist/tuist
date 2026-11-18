---
{
  "title": "What is a flaky test? Causes, detection, and fixes",
  "titleTemplate": ":title · Tuist",
  "description": "A flaky test passes and fails on the same code. Learn the common causes, how flaky test detection works in Xcode, Gradle, and Bazel, and how to measure flakiness."
}
---
# What is a flaky test? {#what-is-a-flaky-test}

A flaky test is an automated test that both passes and fails when it runs against the same code, with nothing in the code under test or the test itself having changed. Its outcome depends on something the test does not control, such as timing, the order tests run in, state left behind by another test, the machine it runs on, or a service it calls over the network. A flaky failure therefore says nothing reliable about the change being tested, which is what makes flaky tests costly: every red result has to be investigated or retried before anyone can trust it.

Flakiness is common at every scale. Google reported that about 1.5% of all its test runs produced a flaky result and that almost 16% of its tests showed some level of flakiness ([Flaky Tests at Google and How We Mitigate Them](https://testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html), 2016).

## How flaky tests show up {#how-flaky-tests-show-up}

A test is only known to be flaky once it has produced both results for the same input. In practice, that evidence comes from one of three places:

- **Retries within a run.** A test fails, the runner retries it, and the retry passes. This is the cheapest signal, and most test runners can produce it.
- **Disagreeing runs of the same commit.** Two CI runs of the same commit and configuration report different results for a test, for example a run on the pull request and a rerun after someone clicks retry.
- **Deliberate repetition.** A test is run many times in a row, on purpose, to see whether it ever fails. This is how teams confirm a suspected flake or check that a new test is stable before merging it.

Results only count as evidence of flakiness when everything that matters is the same: the commit, the build configuration, the device or simulator, the OS version, and the toolchain. A test that fails on iOS 17 and passes on iOS 18 may have a real, deterministic bug on one of them.

## How flaky test detection works per build system {#how-it-works-per-build-system}

Each toolchain can retry and repeat tests, but they record and report the results differently.

### Xcode {#xcode}

`xcodebuild` and test plans support test repetition. `-retry-tests-on-failure` reruns a failing test, `-test-iterations <n>` sets how many attempts are allowed, and `-run-tests-until-failure` repeats a test until it fails, which is useful for reproducing a suspected flake. Test plans expose the same options as a test repetition mode, plus an option to run tests in random order, which surfaces hidden order dependencies.

Every attempt is stored in the `.xcresult` bundle, so a test that failed and then passed on retry is visible there. Xcode does not keep history across runs, so detecting flakes that never retry in the same run requires comparing result bundles from different runs of the same commit.

### Gradle {#gradle}

Gradle's `Test` task does not retry failed tests by itself. The [Test Retry plugin](https://github.com/gradle/test-retry-gradle-plugin) (`org.gradle.test-retry`) adds a `retry` block to `Test` tasks, with options such as `maxRetries` and `failOnPassedAfterRetry`. A test that fails and then passes appears with both attempts in the test reports and JUnit XML. Test frameworks add their own repetition tools, such as JUnit 5's `@RepeatedTest`.

Gradle's build cache can also hide flakiness: a cacheable `Test` task with unchanged inputs is restored from the cache instead of running, so a test that passed once keeps passing without executing. When you are measuring flakiness, force the tests to run with `--rerun-tasks` or by running the `Test` task with the build cache disabled.

### Bazel {#bazel}

Bazel has built-in support. Marking a test target with `flaky = True` makes Bazel run it up to three times and fail it only if every attempt fails. The `--flaky_test_attempts` flag sets the number of attempts without changing the target, and the target's result is reported as `FLAKY` when it passed after a failed attempt. To measure flakiness on purpose, `--runs_per_test=<n>` runs a test many times, and `--runs_per_test_detects_flakes` reports a shard as `FLAKY` when at least one run passes and one fails.

Bazel caches test results the same way it caches build outputs. A test that passed with the same inputs is reported as `(cached) PASSED` without running again, both locally and from a remote cache. Use `--cache_test_results=no` (or `--nocache_test_results`) when you need fresh executions. The Bazel documentation also discourages relying on `flaky = True`, because it permanently hides the failures it retries.

### Other test runners {#other-test-runners}

The same pattern exists almost everywhere: pytest has the `pytest-rerunfailures` plugin, Jest has `jest.retryTimes()`, and Elixir's ExUnit has `mix test --repeat-until-failure` and prints the random seed it used so an order-dependent failure can be replayed with `--seed`.

## Common causes of flaky tests {#common-causes}

An empirical study of flaky tests in open-source projects ([Luo et al., FSE 2014](https://doi.org/10.1145/2635868.2635920)) found asynchronous waiting, concurrency, and test order dependency to be the most common root causes. The list below covers those and the other causes teams run into most often.

- **Asynchronous waits and fixed sleeps.** The test waits a fixed time for work to finish, such as `sleep(1)` or an expectation with a short timeout, and the work sometimes takes longer, especially on a loaded CI machine. Wait for the condition itself, with a generous upper bound.
- **Concurrency.** Two threads or tasks race on shared data, or the test asserts before a background operation completes. These failures often depend on CPU count and load, so they appear on CI and not on a fast laptop.
- **Test order dependence and shared state.** A test relies on state another test created or forgot to clean up: a singleton, a database row, a file on disk, `UserDefaults`, an environment variable, or a mocked global. Running tests in random order or in parallel exposes it.
- **Time and dates.** Tests that use the real clock fail at midnight, at the end of a month, across daylight-saving changes, or in another time zone. Inject a clock instead.
- **Unseeded randomness and unordered collections.** Random data without a recorded seed, or assertions that depend on the iteration order of a hash map or set.
- **Network and external services.** Calls to real APIs, package registries, or shared staging environments fail when those services are slow or unavailable. Stub them at the boundary, and keep a small number of explicit integration tests.
- **Resource pressure and environment state.** Slow or overloaded machines, a simulator or emulator that was not reset, a full disk, or a port another job already uses. When many unrelated tests fail at once, suspect the environment before the tests.
- **UI tests.** End-to-end and UI tests combine most of the causes above with animations, rendering timing, and system dialogs, so they are flaky more often than unit tests.

A test that fails consistently after a change is not flaky; it is a regression. The flaky label should be reserved for tests that have produced both results on the same code.

## Fixing, retrying, and quarantining {#fixing-retrying-and-quarantining}

Teams usually combine three responses, and it helps to keep them separate:

- **Fix** the cause. This is the only response that restores the test's value. The recorded attempts, failure messages, and the conditions of each failing run are the evidence that points to the cause.
- **Retry** to keep pipelines moving. Retries are a useful detection signal, but blanket retries hide the problem and add machine time to every failing run. A retry that passes should still be recorded as a flaky result, not silently discarded.
- **Quarantine** a known flaky test so it stops blocking merges while it is fixed. A quarantined test either still runs with its failures ignored (muted), which keeps producing evidence, or does not run at all (skipped), which removes its coverage. Quarantine needs an owner and an exit condition, or quarantined tests accumulate and coverage quietly shrinks.

## How to measure flakiness {#how-to-measure-flakiness}

Track flakiness per test, not only per pipeline:

- **Flaky rate.** The share of a test's runs that produced a flaky result: a failure followed by a passing retry, or a result that disagrees with another run of the same commit and configuration.
- **Impact.** How many pipelines, pull requests, or merge-queue entries a test blocked or slowed down, and how much machine time its retries consumed. A test with a low flaky rate that runs in every pipeline can cost more than a very flaky test that rarely runs.
- **Trend.** Whether new flaky tests are being introduced faster than old ones are fixed. Repeating new or changed tests several times before they merge catches many flakes at the source.

Confirming that a test is stable takes more runs than intuition suggests. If a test fails with probability *p* on each run, the chance of seeing at least one failure in *n* runs is 1 − (1 − p)ⁿ. For a test that fails 1% of the time, 10 runs catch it only about 10% of the time, and it takes about 300 runs to catch it with 95% confidence. A handful of green reruns is weak evidence that a fix worked.

## When it isn't worth it {#when-it-isnt-worth-it}

Not every flaky test deserves an investigation, and not every team needs flaky test tooling:

- **Low-value tests.** If a flaky test duplicates coverage that other tests already provide, deleting it can be the right fix. A test nobody trusts provides no coverage anyway.
- **Infrastructure problems.** When failures cluster on one machine, runner image, or time of day, fixing the environment is cheaper than fixing tests one by one.
- **Small, fast suites.** For a small team with a fast suite and one known flaky test, a shared note and a fix this week beat a tracking system. Dedicated detection and quarantine pay off when the suite, the number of contributors, or the number of pipelines makes it impossible for anyone to remember which failures are noise.
- **Critical paths.** Quarantine is the wrong tool for a test that guards payments, data integrity, or security. Those tests should block until they are fixed, even if that is inconvenient.

## Flaky test detection with Tuist {#flaky-test-detection-with-tuist}

[Tuist](https://tuist.dev) records every test attempt from Xcode, Gradle, Bazel, Elixir, and other supported integrations, marks a test as flaky when it fails and passes on the same code, both across retries and, for supported integrations, across CI runs of the same commit, and lets teams mute or skip known flaky tests manually or through automations while they are fixed. Support and requirements differ by toolchain:

- <.localized_link href="/guides/features/test-insights/flaky-tests">Flaky tests</.localized_link> explains how detection, quarantine, and stress-testing new tests work, with a guide per toolchain.
- <.localized_link href="/guides/features/test-insights">Test Insights</.localized_link> covers recording test results in the first place.
- [My tests are flaky](https://tuist.dev/solutions/flaky-tests) is a practical guide to diagnosing and containing flaky tests as a team.

Related reference: <.localized_link href="/references/concepts/build-cache">What is a build cache?</.localized_link>, including how cached test results interact with flakiness.
