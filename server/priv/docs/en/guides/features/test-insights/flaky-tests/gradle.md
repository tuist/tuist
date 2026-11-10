---
{
  "title": "Gradle Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect, manage, and quarantine flaky tests in Gradle projects with Tuist."
}
---
# Gradle flaky tests {#gradle-flaky-tests}

> [!IMPORTANT]
> **Requirements**
>
> - <.localized_link href="/guides/features/test-insights/gradle">Gradle test insights</.localized_link> configured.

<!-- @snippet: ./_intro -->

![Flaky Tests page](/images/guides/features/test-insights/flaky-tests-page.png)

## How flaky detection works {#how-it-works}

Tuist detects flaky tests in two ways:

### Test retries {#test-retries}

When you run tests with retry functionality, Tuist analyzes the results of each attempt. If a test fails on some attempts but passes on others, it's marked as flaky.

You can use the [Test Retry plugin](https://github.com/gradle/test-retry-gradle-plugin) or a similar mechanism to re-run failed tests. Tuist will detect tests that pass on some attempts but fail on others.

Add the plugin to your `build.gradle.kts`:

```kotlin
plugins {
    id("org.gradle.test-retry") version "1.6.2"
}

tasks.test {
    retry {
        maxRetries = 3
        maxFailures = 5
        failOnPassedAfterRetry = false
    }
}
```

![Flaky test case detail](/images/guides/features/test-insights/flaky-test-case-detail.png)

### Cross-run detection {#cross-run-detection}

Even without test retries, Tuist can detect flaky tests by comparing results across different CI runs on the same commit and the same Gradle project. If a test passes in one CI run but fails in another run for the same commit and project, the failing execution is marked as flaky.

The Gradle project is part of the comparison key because the same test can behave deterministically differently across projects — for example, a shared test class compiled with different dependencies or run on a different module fixture. Two runs of the same commit on different Gradle projects are treated as separate execution variants and won't flag each other as flaky.

This is particularly useful for catching flaky tests that don't fail consistently enough to be caught by retries, but still cause intermittent CI failures.

<!-- @snippet: ./_managing -->

## Quarantining flaky tests {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

A quarantined test is in one of two modes:

- **Muted**: the test still runs, but the plugin sets `ignoreFailures = true` and only re-fails the build on non-quarantined failures. Failures still feed the flaky-tests detector, so you can keep watching the test without breaking the build. Pick this for a test you're actively investigating.
- **Skipped**: the plugin filters the test out via Gradle's `excludeTestsMatching`, so it never starts. It produces no new results and drops off the flaky-tests dashboard until you re-enable it. Pick this when the test is broken, slow, or so persistently flaky that running it is just wasted CI minutes.

<!-- @snippet: ./_quarantined-passing -->

### Enabling quarantine {#enabling-quarantine}

Quarantine is **automatically enabled on CI** (when the `CI` environment variable is set) and disabled for local builds. The plugin fetches the list of quarantined tests from the Tuist server before each test task; muted tests run normally and have their failures masked, skipped tests are filtered out.

You can explicitly control this in your `settings.gradle.kts`:

```kotlin
tuist {
    testQuarantine {
        enabled = true  // or false to disable
    }
}
```

When `enabled` is not set, it defaults to auto-detection: enabled on CI, disabled locally.

## Stress-testing new tests {#stress-testing-new-tests}

<!-- @snippet: ./_stress-intro -->

A test case counts as new when it hasn't run in CI in the last 90 days on the project's default branch, or on a commit that has since landed on it. With a merge queue, a test case the queue ran is known once the queue's commit lands, and stays new if the queue drops it. Commits are matched through the <.localized_link href="/guides/features/test-insights/gradle#git-history">Git history</.localized_link> Tuist collects on CI.

<!-- @snippet: ./_stress-modes -->

Declare it in `settings.gradle.kts`, or set `TUIST_TEST_STRESS_NEW_TESTS` to vary the mode per CI lane:

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

Unlike quarantine, the gate has no CI-aware default. With no `mode` set it doesn't run anywhere.

<!-- @snippet: ./_stress-reruns -->

Each rerun is a nested Gradle build filtered to that one test case, so every rerun gets a fresh test JVM.

<!-- @snippet: ./_stress-skipped -->

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
