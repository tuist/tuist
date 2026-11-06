---
{
  "title": "Once Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect and investigate flaky Once tests using reported retry attempts and CI history."
}
---
# Once flaky tests {#once-flaky-tests}

> [!IMPORTANT]
> **Requirements**
>
> - Configure <.localized_link href="/guides/features/test-insights/once">Once test insights</.localized_link> with structured individual test results.

<!-- @snippet: ./_intro -->

## How flaky detection works {#how-it-works}

### Test retries {#test-retries}

When a runner reports multiple attempts for the same test, Tuist preserves them. A test that fails and then passes is reported as flaky; one that keeps failing remains a failure. Enable retries in the underlying runner where supported. Connecting Once to Tuist does not automatically add retries to every test target.

### Cross-run detection {#cross-run-detection}

Shared test history also lets Tuist compare passing and failing results for the same test and commit in CI. Once must report the commit and CI context for this comparison; local runs remain visible without becoming automatic cross-run flaky evidence.

Cases are identified by native target, suite, and case name. Keep those identities stable to preserve their history, and use complete per-case reports rather than inferring reliability from a target's overall result.

## Investigate flaky tests {#investigate-flaky-tests}

Open the test case's history in Tuist to compare its attempts, failures, and affected CI commits. Shared test queries are also available through the <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol tools</.localized_link>, so a coding agent can investigate the same reported results.

## Managing flaky tests {#managing-flaky-tests}

You can mark or unmark a test as flaky from its detail page while investigating a failure. The default flaky-test detection automation also clears the flag after its recovery window, normally 14 days without another trigger.

Once projects do not currently expose an **Automations** settings tab. Detection and stored test state are available, but the settings workflow documented for build systems with quarantine enforcement is not yet exposed for Once.

## Quarantine {#quarantining}

Tuist can attribute reported cases to their stored quarantine state, but the native Once client does not currently fetch and enforce Tuist's **Muted** or **Skipped** policies. Changing that state in Tuist does not stop Once from executing the test or make its failure stop blocking CI.

Use your runner's own filtering or failure policy when you need execution-time quarantine. Do not rely on dashboard state alone to change the command's exit code.

## Slack notifications {#slack-notifications}

Once projects do not currently expose the project-settings workflow for configuring flaky-test Slack alerts. Use the shared test queries below to integrate reported flaky state with your own notifications.

<!-- @snippet: ./_querying -->
