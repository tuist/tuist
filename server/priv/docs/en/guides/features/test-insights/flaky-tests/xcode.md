---
{
  "title": "Xcode Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect, manage, and quarantine flaky tests in Xcode projects with Tuist."
}
---
# Xcode flaky tests {#xcode-flaky-tests}

> [!WARNING]
> **Requirements**
>
> - <.localized_link href="/guides/features/test-insights">Test Insights</.localized_link> must be configured


Flaky tests are tests that produce different results (pass or fail) when run multiple times with the same code. They erode trust in your test suite and waste developer time investigating false failures. Tuist automatically detects flaky tests and helps you track them over time.

![Flaky Tests page](/images/guides/features/test-insights/flaky-tests-page.png)

## How flaky detection works {#how-it-works}

Tuist detects flaky tests in two ways:

### Test retries {#test-retries}

When you run tests with retry functionality, Tuist analyzes the results of each attempt. If a test fails on some attempts but passes on others, it's marked as flaky.

Use `-retry-tests-on-failure` or `-test-iterations`:

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

Quarantining isolates a flaky test so it doesn't block CI while you fix it. A quarantined test is in one of two modes:

- **Muted** — the test still runs, but its failure is masked. Use this when you want to keep watching the test (results stay in the run, attached to the flaky-tests dashboard) without breaking the build.
- **Skipped** — the test is excluded from execution entirely via xcodebuild's `-skip-testing` flag. Use this when the test is broken, slow, or persistently flaky and you don't want it to run at all.

> [!IMPORTANT]
> Unless you're using `tuist test`, neither mode is applied automatically: you have to wire up `-skip-testing` for skipped tests yourself when calling xcodebuild directly. Muted tests rely on `tuist test`'s post-run masking, so they only behave as "muted" under `tuist test` or `tuist xcodebuild test`.

### Setting the mode {#setting-the-mode}

Open a test case from the Test Cases page and use the **State** dropdown to flip between **Enabled**, **Muted**, and **Skipped**. The Quarantined Tests page lists every quarantined test alongside its mode, with a Mode filter to narrow down to one or the other.

### Automating it {#automating}

Automations can move tests between states for you — for example, when a test crosses a flakiness threshold, set it to Muted (or straight to Skipped) and post a message to the right Slack channel. Configure them under your project's **Automations** tab.

### Running tests {#running-tests}

#### With tuist test

`tuist test` honours both modes automatically:

```bash
tuist test
```

Skipped tests are passed to xcodebuild as `-skip-testing` and never start. Muted tests run normally; if they fail, the failure is masked in the resulting build status.

To bypass quarantine entirely and run everything, including muted and skipped tests:

```bash
tuist test --skip-quarantine
```

#### With xcodebuild directly

When invoking xcodebuild yourself, use `tuist test case list --quarantined --skip-testing` to expand every quarantined test (muted and skipped) into `-skip-testing` arguments:

```bash
xcodebuild test \
  -scheme MyScheme \
  $(tuist test case list --quarantined --skip-testing)
```

This is the safe default outside `tuist test` / `tuist xcodebuild test`: failure masking for muted tests only happens through those commands, so skipping both modes avoids spurious CI failures. If you need finer control, go through `tuist test` instead.

## Slack notifications {#slack-notifications}

Get notified instantly when a test becomes flaky by setting up <.localized_link href="/guides/integrations/slack#flaky-test-alerts">flaky test alerts</.localized_link> in your Slack integration.
