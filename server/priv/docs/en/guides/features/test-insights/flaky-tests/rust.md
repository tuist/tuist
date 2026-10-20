---
{
  "title": "Rust Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect and investigate flaky Cargo tests using CI history."
}
---
# Rust flaky tests {#rust-flaky-tests}

Tuist can detect inconsistent Cargo test results and help you investigate them in **Tests → Flaky Tests**.

> [!IMPORTANT] Requirements
> - Configure <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link>.

## How flaky detection works {#how-it-works}

Tuist compares CI runs on the same commit. A test that passes in one run and fails in another can be marked as flaky.

Report each run through the usual command:

```sh
tuist cargo test --workspace
```

Cargo does not automatically retry failed tests. Re-running a CI job on the same commit provides another result for cross-run detection.

## Managing flaky tests {#managing-flaky-tests}

### Automatic clearing

Detection and recovery run through the project's "Flaky test detection" automation. By default, the flaky flag clears after 14 days without re-triggering. Edit the recovery window and actions under **Settings → Automations**.

### Manual management

Open **Tests → Flaky Tests** to inspect a test's history. You can manually mark or unmark it as flaky from its detail page.

## Quarantining and stress-testing {#quarantine}

The Cargo integration does not apply quarantine yet: tests muted or skipped in the dashboard still run, and their failures still affect the result. It does not stress-test new tests either. Use a Cargo test filter to repeat a failing test while investigating it:

```sh
tuist cargo test -p store rejects_invalid_token
```

## Slack notifications {#notifications}

Configure <.localized_link href="/guides/integrations/slack#flaky-test-alerts">Slack flaky test alerts</.localized_link> to notify your team when a test becomes flaky.
