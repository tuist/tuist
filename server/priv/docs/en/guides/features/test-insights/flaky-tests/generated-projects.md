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

## How tests are tracked {#tracking}

A test case is identified by `(project, module, suite, name)` and tracked at the **individual test level** — not by class or suite. Tracking is **project-wide**, not per-branch: runs from any branch contribute to the same test case's history, so a test that only flakes on one branch shows up in the project's flaky-tests view.

A test only becomes flaky if it has produced **both a passing and a failing result** for the same code. A test that fails on every attempt is a failing test, not a flaky one.

`is_flaky` (auto-detected) and the quarantine state (`enabled` / `muted` / `skipped`, set manually) are **independent dimensions**. A test is commonly flaky and muted at the same time.

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

Detection and clearing run through an **automation alert** on the project. Every project gets a default "Flaky test detection" automation whose *trigger* marks a test as flaky and whose *recovery* clears the flag once the test has gone the configured recovery window (default **14 days**) without re-triggering. Edit it under **Settings → Automations** to change the recovery window, swap the recovery actions (e.g. also un-quarantine), or disable recovery entirely so tests stay marked flaky until you clear them by hand.

### Manual management

You can also manually mark or unmark tests as flaky from the test case detail page. This is useful when:
- You want to acknowledge a known flaky test while working on a fix
- A test was incorrectly flagged due to infrastructure issues

## Quarantining flaky tests {#quarantining}

Quarantining isolates a flaky test so it doesn't block CI while you fix it. By default it's a **manual action** — you quarantine, un-quarantine, and switch modes from the test case detail page in the dashboard — but you can also wire it into an **automation alert** under **Settings → Automations** by adding a `change_state` trigger action (e.g. auto-mute on a 10% flakiness rate over 30 days) and a matching recovery action to un-quarantine when the test recovers. Every transition, manual or automated, is recorded as an event (`muted`, `unmuted`, `skipped`, `unskipped`) on the test case's audit log.

A quarantined test is in one of two modes:

- **Muted**: the test still runs, but `tuist test` masks the failure. Failures still feed the flaky-tests detector, so you can keep watching the test without breaking the build. Pick this for a test you're actively investigating.
- **Skipped**: xcodebuild receives `-skip-testing <identifier>`, so the test never starts. It produces no new results and drops off the flaky-tests dashboard until you re-enable it. Pick this when the test is broken, slow, or so persistently flaky that running it is just wasted CI minutes.

### Why quarantined tests can appear as passing {#quarantined-passing}

- **Muted tests** still execute and may genuinely fail, but the runner masks the failure so the build passes. The underlying run is recorded with its real status, but build-level summaries show it as a pass.
- **Skipped tests** don't run at all, so `last_status` and `last_ran_at` are not updated — what you see is the *last status before the test was skipped*, which can be weeks old.

### Stale quarantined tests {#stale-quarantined-tests}

Test cases are not hard-deleted from Tuist when you delete or rename them in source. The default views filter out test cases inactive for 14 days, but **quarantined tests intentionally bypass that filter** so a long-forgotten quarantined test isn't silently re-enabled. Renaming a test creates a new identity (since identity is `module + suite + name`); the old identity is orphaned but stays in the data. To drop a stale entry from the dashboard, un-quarantine it first — the inactive-window filter will then hide it from default views.

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
