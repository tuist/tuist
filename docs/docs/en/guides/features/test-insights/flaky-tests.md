---
{
  "title": "Flaky Tests",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Automatically detect and track flaky tests in your CI pipelines."
}
---
# Flaky Tests {#flaky-tests}

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

When you run tests with Xcode's retry functionality (using `-retry-tests-on-failure` or `-test-iterations`), Tuist analyzes the results of each attempt. If a test fails on some attempts but passes on others, it's marked as flaky.

For example, if a test fails on the first attempt but passes on the retry, Tuist records this as a flaky test.

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -retry-tests-on-failure \
  -test-iterations 3
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

Quarantining allows you to isolate flaky tests so they don't block your CI pipeline while you work on fixing them. Quarantined tests can be skipped during test runs, preventing false failures from disrupting your team's workflow.

> [!IMPORTANT]
> Quarantining a test does not automatically skip it. You must explicitly pass the list of quarantined tests to xcodebuild using the `-skip-testing` flag.

### Automatic quarantine

When enabled in your project's Automations settings, tests are automatically quarantined when they're marked as flaky. This ensures that newly detected flaky tests are immediately isolated without manual intervention.

To enable automatic quarantine:
1. Go to your project settings
2. Navigate to the **Automations** tab
3. Enable **Auto-quarantine flaky tests**

### Manual quarantine

You can also manually quarantine or unquarantine tests from the test case detail page using the **Quarantine** and **Unquarantine** buttons. This is useful when:
- You want to quarantine a test before it's automatically detected as flaky
- You want to unquarantine a test after fixing the underlying issue

### Skipping quarantined tests with xcodebuild {#skipping-quarantined-tests}

Use the `tuist test case list` command with the `--skip-testing` flag to get quarantined test identifiers formatted for xcodebuild:

```bash
xcodebuild test \
  -scheme MyScheme \
  $(tuist test case list --skip-testing)
```

## Slack notifications {#slack-notifications}

Get notified instantly when a test becomes flaky by setting up <LocalizedLink href="/guides/integrations/slack#flaky-test-alerts">flaky test alerts</LocalizedLink> in your Slack integration.
