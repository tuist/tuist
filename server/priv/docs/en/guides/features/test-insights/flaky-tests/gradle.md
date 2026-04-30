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

## How tests are tracked {#tracking}

A test case is identified by `(project, module, suite, name)` and tracked at the **individual test level** — not by class or suite. Tracking is **project-wide**, not per-branch: runs from any branch contribute to the same test case's history, so a test that only flakes on one branch shows up in the project's flaky-tests view.

A test only becomes flaky if it has produced **both a passing and a failing result** for the same code. A test that fails on every attempt is a failing test, not a flaky one.

`is_flaky` (auto-detected) and the quarantine state (`enabled` / `muted` / `skipped`, set manually) are **independent dimensions**. A test is commonly flaky and muted at the same time.

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

Tuist automatically clears the flaky flag from tests that haven't been flaky for the configured cooldown window (default **14 days**). This ensures tests that have been fixed don't remain marked as flaky indefinitely. The window is configurable per project via the `flaky_cooldown_days` setting.

### Manual management

You can also manually mark or unmark tests as flaky from the test case detail page. This is useful when:
- You want to acknowledge a known flaky test while working on a fix
- A test was incorrectly flagged due to infrastructure issues

## Quarantining flaky tests {#quarantining}

Quarantining isolates a flaky test so it doesn't block CI while you fix it. Quarantine is **always a manual action** — there's no automatic threshold that quarantines a test on your behalf, since deciding when a test is too noisy to keep running is a judgment call that deserves a human in the loop. You quarantine, un-quarantine, and switch modes from the test case detail page in the dashboard. Every transition is recorded as an event (`muted`, `unmuted`, `skipped`, `unskipped`) on the test case's audit log.

A quarantined test is in one of two modes:

- **Muted**: the test still runs, but the plugin sets `ignoreFailures = true` and only re-fails the build on non-quarantined failures. Failures still feed the flaky-tests detector, so you can keep watching the test without breaking the build. Pick this for a test you're actively investigating.
- **Skipped**: the plugin filters the test out via Gradle's `excludeTestsMatching`, so it never starts. It produces no new results and drops off the flaky-tests dashboard until you re-enable it. Pick this when the test is broken, slow, or so persistently flaky that running it is just wasted CI minutes.

### Why quarantined tests can appear as passing {#quarantined-passing}

- **Muted tests** still execute and may genuinely fail, but the plugin masks the failure so the build passes. The underlying run is recorded with its real status, but build-level summaries show it as a pass.
- **Skipped tests** don't run at all, so `last_status` and `last_ran_at` are not updated — what you see is the *last status before the test was skipped*, which can be weeks old.

### Stale quarantined tests {#stale-quarantined-tests}

Test cases are not hard-deleted from Tuist when you delete or rename them in source. The default views filter out test cases inactive for 14 days, but **quarantined tests intentionally bypass that filter** so a long-forgotten quarantined test isn't silently re-enabled. Renaming a test creates a new identity (since identity is `module + suite + name`); the old identity is orphaned but stays in the data. To drop a stale entry from the dashboard, un-quarantine it first — the inactive-window filter will then hide it from default views.

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

## Querying flaky and quarantined state {#querying}

### CLI

The `tuist test case` command tree exposes everything Tuist tracks about a test case:

```sh
tuist test case list --flaky                       # only flaky test cases
tuist test case list --quarantined                 # only muted or skipped test cases
tuist test case show <test_case_id>                # detail: flakiness rate, last status, run counts
tuist test case events <test_case_id>              # audit log: marked_flaky, muted, skipped, ...
tuist test case run list <test_case_id>            # run history with status and duration
tuist test case run show <test_case_run_id>        # single run, including failure breakdown
```

All of these accept `--json` for scripting.

### REST API

The same data is available under `/api/projects/{account_handle}/{project_handle}/tests/test-cases`:

| Endpoint | Purpose |
| --- | --- |
| `GET /test-cases` | List, with filters: `flaky`, `quarantined`, `state` (`enabled` / `muted` / `skipped`), `module_name`, `suite_name`, `name`. |
| `GET /test-cases/{test_case_id}` | Detail: `is_flaky`, `state`, `last_status`, `flakiness_rate` (% over the last 30 days), `total_runs`, `failed_runs`. |
| `GET /test-cases/{test_case_id}/events` | Immutable audit log of state transitions. |
| `GET /test-cases/{test_case_id}/runs` | Paginated run history. |
| `GET /test-cases/runs/{test_case_run_id}` | One run, including per-repetition statuses and failure messages. |

State changes (mark/unmark flaky, mute, skip) currently happen from the dashboard UI, not via the public REST API.

## Slack notifications {#slack-notifications}

Get notified instantly when a test becomes flaky by setting up <.localized_link href="/guides/integrations/slack#flaky-test-alerts">flaky test alerts</.localized_link> in your Slack integration.
