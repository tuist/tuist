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

Pass `-retry-tests-on-failure` or `-test-iterations` through `tuist xcodebuild test`:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -retry-tests-on-failure \
  -test-iterations 3
```

![Flaky test case detail](/images/guides/features/test-insights/flaky-test-case-detail.png)

### Cross-run detection {#cross-run-detection}

Even without test retries, Tuist can detect flaky tests by comparing results across different CI runs on the same commit and the same scheme. If a test passes in one CI run but fails in another run for the same commit and scheme, both runs are marked as flaky.

The scheme is part of the comparison key because the same test can behave deterministically differently across schemes — for example, a snapshot test that's only valid against a specific simulator destination, or a test target that's compiled with different flags. Two runs of the same commit on different schemes are treated as separate execution variants and won't flag each other as flaky.

This is particularly useful for catching flaky tests that don't fail consistently enough to be caught by retries, but still cause intermittent CI failures.

## Managing flaky tests {#managing-flaky-tests}

### Automatic clearing

Detection and clearing run through an **automation alert** on the project. Every project gets a default "Flaky test detection" automation whose *trigger* marks a test as flaky and whose *recovery* clears the flag once the test has gone the configured recovery window (default **14 days**) without re-triggering. Edit it under **Settings → Automations** to change the recovery window, swap the recovery actions (e.g. also un-quarantine), or disable recovery entirely so tests stay marked flaky until you clear them by hand.

### Manual management

You can also manually mark or unmark tests as flaky from the test case detail page. This is useful when:
- You want to acknowledge a known flaky test while working on a fix
- A test was incorrectly flagged due to infrastructure issues

### Applying automation actions to existing matches

Select **Apply to existing matches** immediately above **Create** or **Save** to run trigger actions for tests that already satisfy the condition and state scope. The form shows how many tests currently match, including the state scope and default-branch validation. This count refreshes as you change the condition and is a preview: matches can change before actions run. This is useful for recovery automations that re-enable healthy tests or remove their flaky label. By default, the first evaluation records existing matches silently and only later transitions run actions.

This is a one-time choice for that save, including all configured Slack notifications. The checkbox starts unchecked whenever you open the editor. Use **When** to configure the condition, **What** for actions, and **Recovery** for recovery behavior. When creating an automation, When and What start expanded and Recovery starts collapsed. When editing, all sections start collapsed with a summary of their configuration. Later condition or action edits do not repeat actions unless you select it again. You can also select it without changing the condition to process an existing backlog. Processing happens on the next evaluation. Interrupted jobs resume from their completed tests; a reported action failure is logged without blocking the remaining matches or future evaluations. Applying an existing backlog preserves recovery tracking for previously triggered tests.

If a request is still pending, the editor shows a notice. Save with the checkbox unchecked to cancel remaining actions. Actions that have already run are not undone.

The API accepts the same one-time request as a boolean at `trigger_config.apply_actions_to_existing_matches`. Submit `true` explicitly for each save that should process existing matches. Submit `false` to cancel remaining work; omitting the key on an unrelated update preserves a pending request. The request is cleared after processing completes. Event-driven automations do not support it.

## Quarantining flaky tests {#quarantining}

Quarantining isolates a flaky test so it doesn't block CI while you fix it. By default it's a **manual action** — you quarantine, un-quarantine, and switch modes from the test case detail page in the dashboard — but you can also wire it into an **automation alert** under **Settings → Automations** so a test is automatically muted (or skipped) when it crosses a flakiness threshold, and un-quarantined when it recovers. Every transition, manual or automated, is recorded on the test case's audit log.

A quarantined test is in one of two modes:

- **Muted**: the test still runs, but `tuist xcodebuild test` masks the failure. Failures still feed the flaky-tests detector, so you can keep watching the test without breaking the build. Pick this for a test you're actively investigating.
- **Skipped**: xcodebuild receives `-skip-testing <identifier>`, so the test never starts. It produces no new results and drops off the flaky-tests dashboard until you re-enable it. Pick this when the test is broken, slow, or so persistently flaky that running it is just wasted CI minutes.

### Why quarantined tests can appear as passing {#quarantined-passing}

- **Muted tests** still execute. A muted test that fails is recorded as **failed** on the test case run and flagged as flaky — the per-test status is not rewritten. What gets overridden is the **overall test run**: if every failing test case in the run is muted, the run as a whole is reported as passed, so muted failures don't break CI.
- **Skipped tests** don't run at all, so the dashboard keeps showing the status from the test's last actual execution — that snapshot can be weeks old.

### Running tests {#running-tests}

`tuist xcodebuild test` is a passthrough wrapper that honours both modes automatically. Use it the same way you'd call xcodebuild:

```sh
tuist xcodebuild test -scheme MyScheme
```

Skipped tests are appended to your xcodebuild invocation as `-skip-testing <identifier>` and never start. Muted tests run normally; if they fail, the failure is masked in the resulting build status.

#### Bypassing quarantine

`tuist xcodebuild test` accepts `--skip-quarantine` to run everything, including muted and skipped tests:

```sh
tuist xcodebuild test --skip-quarantine -scheme MyScheme
```

#### Calling xcodebuild directly

If you can't go through `tuist xcodebuild test`, expand the quarantined tests into `-skip-testing` arguments yourself with `tuist test case list`:

```sh
xcodebuild test \
  -scheme MyScheme \
  $(tuist test case list --quarantined --skip-testing)
```

This is the safe default outside `tuist xcodebuild test`: failure masking for muted tests only happens when you go through that command, so skipping both modes avoids spurious CI failures. If you need finer control, go through `tuist xcodebuild test` instead.

## Stress-testing new tests {#stress-testing-new-tests}

The stress gate reruns the test cases your branch adds, several times each in a fresh process, and reports the ones that turn out flaky. You see a new flaky test on the pull request that introduced it, not weeks later.

A test case counts as new when it hasn't run in CI on the project's default branch in the last 90 days.

### Enabling it

The gate is off by default. Set a mode:

- **`report`**: warns about each flaky test case. The run still exits on its own result.
- **`enforce`**: a flaky test case fails the run, with the same exit code as a failed test.

Start with `report` for a couple of weeks to see what `enforce` would have blocked.

Pass it ahead of the passthrough arguments, or set `TUIST_TEST_STRESS_NEW_TESTS` to vary the mode per CI lane:

```sh
tuist xcodebuild test --stress-new-tests report -scheme MyScheme
```

### How many times each test reruns

It depends on how long the test case took on the first pass:

| First pass | Reruns |
| --- | --- |
| Up to 5s | 10 |
| Up to 10s | 5 |
| Up to 30s | 3 |
| Up to 5min | 2 |
| Over 5min | Not rerun |

Reruns reuse what the first pass built. The pass stops at 200 test cases or 10 minutes, whichever comes first, and says which limit it hit.

### When the gate doesn't run

- The first pass already failed. Fix those tests first.
- The project has no default branch, or nothing has run in CI on it yet.
- More than 30% of the project's test cases look new. Rerunning that many would take longer than it's worth. Expect this on a project that only just started reporting to Tuist, or after a rename that moves a lot of tests at once.

## Slack notifications {#slack-notifications}

Get notified instantly when a test becomes flaky by setting up <.localized_link href="/guides/integrations/slack#flaky-test-alerts">flaky test alerts</.localized_link> in your Slack integration.

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

The same data is available over HTTP — see the [Test Cases endpoints](https://tuist.dev/api/docs#tag/test-cases) in the API reference for the full list of routes, filters, and response fields. State changes (mark/unmark flaky, mute, skip) currently happen from the dashboard UI, not via the public REST API.
