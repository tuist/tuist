---
{
  "title": "Gradle Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect, manage, and quarantine flaky tests in Gradle projects with Tuist."
}
---
# Gradle flaky tests {#gradle-flaky-tests}

> [!WARNING]
> **Requirements**
>
> - The <.localized_link href="/guides/install-gradle-plugin">Tuist Gradle plugin</.localized_link> installed and configured


Flaky tests are tests that produce different results (pass or fail) when run multiple times with the same code. They erode trust in your test suite and waste developer time investigating false failures. Tuist automatically detects flaky tests and helps you track them over time.

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

Even without test retries, Tuist can detect flaky tests by comparing results across different CI runs on the same commit. If a test passes in one CI run but fails in another run for the same commit, both runs are marked as flaky.

This is particularly useful for catching flaky tests that don't fail consistently enough to be caught by retries, but still cause intermittent CI failures.

## Managing flaky tests {#managing-flaky-tests}

### Automatic clearing

Tuist automatically clears the flaky flag from tests that haven't been flaky for 14 days. This ensures that tests that have been fixed don't remain marked as flaky indefinitely.

### Manual management

You can also manually mark or unmark tests as flaky from the test case detail page. This is useful when:
- You want to acknowledge a known flaky test while working on a fix
- A test was incorrectly flagged due to infrastructure issues

## Quarantining flaky tests {#quarantining}

Quarantining isolates a flaky test so it doesn't block CI while you fix it. A quarantined test is in one of two modes (**Muted** or **Skipped**) that differ in whether the test runs at all and whether you still get signal from it:

|                                | **Muted**                                                                                  | **Skipped**                                       |
| ------------------------------ | ------------------------------------------------------------------------------------------ | ------------------------------------------------- |
| Does the test run?             | Yes                                                                                        | No, excluded via Gradle's `excludeTestsMatching`  |
| Does a failure fail the build? | No; the plugin sets `ignoreFailures = true` and only re-fails on non-quarantined failures  | N/A, the test never runs                          |
| Does it still count as flaky?  | Yes; failures still feed the flaky-tests detector                                          | No (the test produces no new results)             |
| Test duration on CI            | Same as before                                                                             | Zero (the test is filtered out)                   |

**Pick Muted when** you want to keep watching the test (see if it stabilizes, when it stops being flaky, how often it actually fails) without that failure breaking the build.

**Pick Skipped when** the test is broken, slow, or so persistently flaky that running it is just wasted CI minutes and noise. Skipped tests don't produce results, so they drop off your flaky-tests dashboard until you re-enable them.

### Setting the mode {#setting-the-mode}

Open a test case from the Test Cases page and use the **State** dropdown to flip between **Enabled**, **Muted**, and **Skipped**. The Quarantined Tests page lists every quarantined test alongside its mode, with a Mode filter to narrow down to one or the other. Automations can drive the same transitions. For example, auto-Mute a test once it crosses a flakiness threshold and post a message to Slack.

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

## Slack notifications {#slack-notifications}

Get notified instantly when a test becomes flaky by setting up <.localized_link href="/guides/integrations/slack#flaky-test-alerts">flaky test alerts</.localized_link> in your Slack integration.
