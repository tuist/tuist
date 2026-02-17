---
{
  "title": "Gradle Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect and manage flaky tests in Gradle projects with Tuist."
}
---
# Gradle flaky tests {#gradle-flaky-tests}

::: warning REQUIREMENTS
<!-- -->
- <LocalizedLink href="/guides/features/test-insights">Test Insights</LocalizedLink> must be configured
<!-- -->
:::

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

## Slack notifications {#slack-notifications}

Get notified instantly when a test becomes flaky by setting up <LocalizedLink href="/guides/integrations/slack#flaky-test-alerts">flaky test alerts</LocalizedLink> in your Slack integration.
