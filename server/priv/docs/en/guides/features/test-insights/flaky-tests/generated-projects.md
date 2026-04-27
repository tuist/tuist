---
{
  "title": "Generated Projects Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect, manage, and quarantine flaky tests in Tuist generated projects."
}
---
# Generated projects flaky tests {#generated-projects-flaky-tests}

> [!WARNING]
> **Requirements**
>
> - A <.localized_link href="/guides/features/projects">Tuist generated project</.localized_link>
> - <.localized_link href="/guides/features/test-insights">Test Insights</.localized_link> must be configured


Flaky tests are tests that produce different results (pass or fail) when run multiple times with the same code. They erode trust in your test suite and waste developer time investigating false failures. Tuist automatically detects flaky tests and helps you track them over time.

![Flaky Tests page](/images/guides/features/test-insights/flaky-tests-page.png)

## How flaky detection works {#how-it-works}

Tuist detects flaky tests in two ways:

### Test retries {#test-retries}

When you run tests with retry functionality, Tuist analyzes the results of each attempt. If a test fails on some attempts but passes on others, it's marked as flaky.

Pass `-retry-tests-on-failure` or `-test-iterations` through `tuist test`:

```sh
tuist test --scheme MyScheme -- -retry-tests-on-failure -test-iterations 3
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

Quarantining isolates a flaky test so it doesn't block CI while you fix it. A quarantined test is in one of two modes:

- **Muted**: the test still runs, but `tuist test` masks the failure. Failures still feed the flaky-tests detector, so you can keep watching the test without breaking the build. Pick this for a test you're actively investigating.
- **Skipped**: xcodebuild receives `-skip-testing <identifier>`, so the test never starts. It produces no new results and drops off the flaky-tests dashboard until you re-enable it. Pick this when the test is broken, slow, or so persistently flaky that running it is just wasted CI minutes.

### Setting the mode {#setting-the-mode}

Open a test case from the Test Cases page and use the **State** dropdown to flip between **Enabled**, **Muted**, and **Skipped**. The Quarantined Tests page lists every quarantined test alongside its mode, with a Mode filter to narrow down to one or the other. Automations can move tests between states for you too. For example, when a test crosses a flakiness threshold, set it to Muted (or straight to Skipped) and post a message to the right Slack channel. Configure them under your project's **Automations** tab.

### Running tests {#running-tests}

`tuist test` honours both modes automatically:

```sh
tuist test
```

Skipped tests are passed to xcodebuild as `-skip-testing` and never start. Muted tests run normally; if they fail, the failure is masked in the resulting build status.

To bypass quarantine entirely and run everything, including muted and skipped tests:

```sh
tuist test --skip-quarantine
```

## Slack notifications {#slack-notifications}

Get notified instantly when a test becomes flaky by setting up <.localized_link href="/guides/integrations/slack#flaky-test-alerts">flaky test alerts</.localized_link> in your Slack integration.
