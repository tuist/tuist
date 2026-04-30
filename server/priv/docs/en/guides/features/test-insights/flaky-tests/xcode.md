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

## Slack notifications {#slack-notifications}

Get notified instantly when a test becomes flaky by setting up <.localized_link href="/guides/integrations/slack#flaky-test-alerts">flaky test alerts</.localized_link> in your Slack integration.
