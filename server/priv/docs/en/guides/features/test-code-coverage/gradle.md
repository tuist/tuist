---
{
  "title": "Gradle Code Coverage",
  "titleTemplate": ":title · Code Coverage · Features · Guides · Tuist",
  "description": "Upload the code coverage of your Gradle project's tests, measured with JaCoCo, and follow it per file, per project and per commit."
}
---
# Gradle code coverage {#gradle-code-coverage}

Code coverage tells you which lines of your code your tests executed. The Tuist Gradle plugin measures the coverage of your test tasks with JaCoCo and uploads it with each test run, and Tuist folds the runs of a commit into one figure, for the project, each Gradle project and each file. The dashboard's **Code Coverage** page shows it per commit and as a trend for each branch.

> [!IMPORTANT]
> **Requirements**
>
> - The `dev.tuist` Gradle plugin applied, as described in <.localized_link href="/guides/get-started/gradle-project">Get started with a Gradle project</.localized_link>
> - Your project in a Git repository: a run outside one uploads its test results but no coverage

> [!NOTE]
> **Early access**
>
> Code coverage for Gradle projects is in early access. [Reach out](mailto:contact@tuist.dev) to turn it on for your account. Until then, Tuist doesn't store the coverage your runs upload.

## Setup {#setup}

### Turn coverage on {#turn-coverage-on}

Turn coverage on in the `tuist` block of your `settings.gradle.kts`:

```kotlin
tuist {
    coverage {
        enabled = true
    }
}
```

Or turn it on for one invocation, such as a CI job, with an environment variable, which takes precedence over the setting either way:

```sh
TUIST_TEST_COVERAGE=1 ./gradlew test
```

With coverage on, the plugin applies Gradle's `jacoco` plugin to every JVM project. JaCoCo's agent comes from your project's repositories, as it would if you applied the plugin yourself. A project that already configures JaCoCo keeps its settings, and its own reports keep working.

### Complete each commit on CI {#complete-each-commit}

A commit's coverage often comes from several jobs, such as one per shard. Tuist can't tell when the last of them has reported, so tell it. Once every test job for a commit has finished, run this in a job that depends on all of them:

```sh
./gradlew tuistCoverageComplete
```

The task reads the commit from `GIT_COMMIT` or the checkout's `HEAD`; pass `-Ptuist.coverage.commit=<sha>` to name another one. Until a commit is complete, its coverage shows as **In progress** and stays out of its branch's trend.

## How it works {#how-it-works}

### What Tuist measures {#what-tuist-measures}

- **Projects.** Each Gradle project is a module on the dashboard, with its own coverage.
- **Product code only.** Classes compiled from test source sets are test code. Tuist stores them but leaves them out of every figure.
- **Your repository's files.** A class counts for the source file it was compiled from, under its path in your repository. Generated sources and files Git ignores aren't reported.
- **Whether each line ran.** JaCoCo records whether code ran, not how many times, so the dashboard's execution counts are 0 or 1.

### Which code each test ran {#per-test-evidence}

For tests that run on the JUnit Platform (JUnit 5, or JUnit 4 through JUnit Vintage), the plugin also records which code each test ran, and what each test class ran outside its tests, such as in `@BeforeAll`. That is what lets Tuist carry forward the coverage of tests a run leaves out (see [Skipped tests](#skipped-tests)). Nothing needs to be added to your tests.

This works when each test JVM runs one test at a time, which is how Gradle runs tests unless you turn on JUnit's parallel execution. Running test classes in several JVMs with `maxParallelForks` is fine. Tests that run at the same time in one JVM still count in the coverage, but not one by one.

### The build cache {#build-cache}

A test task Gradle restores from the build cache, or that is up to date, runs no tests. Its coverage is still uploaded: JaCoCo's data is one of the task's outputs, recorded by the run that executed its tests on the same inputs.

### Skipped tests {#skipped-tests}

When a run leaves tests out, Tuist fills in what they covered from an earlier run, as long as the code they ran is unchanged. When it can't, the commit's coverage is **Incomplete**. What a run leaves out:

- **A project's test task excluded** with `-x :app:test`. Its tests are carried forward from the last run of them whose code is unchanged.
- **Some projects' tests** with `./gradlew :core:test`, or **some tests** with `--tests`. The run covers only what you asked for, so the commit is incomplete unless another run of the commit ran everything.
- **A test task that stopped at its first failure** (`failFast`).

Some tests are left out on purpose and don't make a commit incomplete:

- **Filters in your build script**, such as `filter { excludeTestsMatching(...) }`, which define what your suite runs.
- **Test tasks your build script turns off**, with `enabled = false` or an `onlyIf` that skips them.
- **Tests that <.localized_link href="/guides/features/test-insights/flaky-tests/gradle">quarantine</.localized_link> skips.** They're left out as if they had been removed, so the lines only they covered count as uncovered.

When you <.localized_link href="/guides/features/test-sharding/gradle">shard your tests</.localized_link>, each shard reports the coverage of the tests it ran, and Tuist merges the shards of a run into one figure.

### Complete and incomplete commits {#commit-status}

| Status | Meaning |
| --- | --- |
| In progress | Runs have reported coverage, but `tuistCoverageComplete` hasn't run for the commit yet. |
| Complete | Every test of the commit's runs ran, was carried forward, or was left out on purpose. |
| Incomplete | Some coverage couldn't be determined, so the figure is a lower bound. |
| Not measured | No run reported coverage for the commit. |

A branch's trend only includes complete commits.

## Limitations {#limitations}

- **Isolated Projects and configuration on demand.** These builds don't configure every project, so the plugin can't tell which projects' tests a run left out, and a run of some projects' tests counts as complete.
- **No coverage from pull requests from forks.** Coverage is uploaded only by runs that authenticate with Tuist, and CI usually withholds secrets and identity tokens from pull requests opened from forks.

## Querying coverage {#querying}

The dashboard's **Code Coverage** page shows each commit's figure, its modules and its files, with the lines each run covered. The same data is available to agents through the <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol server</.localized_link>.
