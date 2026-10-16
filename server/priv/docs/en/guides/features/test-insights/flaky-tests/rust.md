---
{
  "title": "Rust Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect and investigate flaky nextest tests using retry attempts and CI history."
}
---
# Rust flaky tests {#rust-flaky-tests}

Tuist can detect inconsistent nextest results and help you investigate them in **Tests → Flaky Tests**.

> [!IMPORTANT] Requirements
> - Configure <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link>.

## How flaky detection works {#how-it-works}

Tuist detects flaky tests from retry attempts and results across CI runs.

### Test retries {#test-retries}

Enable nextest retries on the command line:

```sh
tuist cargo nextest run --retries 2
```

Or configure your existing `.config/nextest.toml`:

```toml
[profile.ci]
retries = 2
```

Run the selected profile:

```sh
tuist cargo nextest run --profile ci
```

When a test fails and then passes on a retry, Tuist marks it as flaky. Nextest controls the retries and the final result of the run.

### Cross-run detection {#cross-run-detection}

Even without retries, Tuist can detect flaky tests by comparing CI runs on the same commit. A test that passes in one run and fails in another can be marked as flaky.

## Managing flaky tests {#managing-flaky-tests}

### Automatic clearing

Detection and recovery run through the project's "Flaky test detection" automation. By default, the flaky flag clears after 14 days without re-triggering. Edit the recovery window and actions under **Settings → Automations**.

### Manual management

Open **Tests → Flaky Tests** to inspect a test's history and retry attempts. You can manually mark or unmark it as flaky from its detail page.

## Quarantining and stress-testing {#quarantine}

The Cargo integration does not apply quarantine yet: tests muted or skipped in the dashboard still run with nextest, and their failures still affect the result. It does not stress-test new tests either. Use [test retries](#test-retries) while fixing a flaky test.

## Slack notifications {#notifications}

Configure <.localized_link href="/guides/integrations/slack#flaky-test-alerts">Slack flaky test alerts</.localized_link> to notify your team when a test becomes flaky.
