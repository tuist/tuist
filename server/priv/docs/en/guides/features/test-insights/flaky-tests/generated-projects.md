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

## Quarantining flaky tests {#quarantining}

Quarantining isolates a flaky test so it doesn't block CI while you fix it. By default it's a **manual action** — you quarantine, un-quarantine, and switch modes from the test case detail page in the dashboard — but you can also wire it into an **automation alert** under **Settings → Automations** so a test is automatically muted (or skipped) when it crosses a flakiness threshold, and un-quarantined when it recovers. Every transition, manual or automated, is recorded on the test case's audit log.

A quarantined test is in one of two modes:

- **Muted**: the test still runs, but `tuist test` masks the failure. Failures still feed the flaky-tests detector, so you can keep watching the test without breaking the build. Pick this for a test you're actively investigating.
- **Skipped**: xcodebuild receives `-skip-testing <identifier>`, so the test never starts. It produces no new results and drops off the flaky-tests dashboard until you re-enable it. Pick this when the test is broken, slow, or so persistently flaky that running it is just wasted CI minutes.

### Why quarantined tests can appear as passing {#quarantined-passing}

- **Muted tests** still execute. A muted test that fails is recorded as **failed** on the test case run and flagged as flaky — the per-test status is not rewritten. What gets overridden is the **overall test run**: if every failing test case in the run is muted, the run as a whole is reported as passed, so muted failures don't break CI.
- **Skipped tests** don't run at all, so the dashboard keeps showing the status from the test's last actual execution — that snapshot can be weeks old.

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

## Stress-testing new tests {#stress-testing-new-tests}

Flaky tests are cheapest to fix while their author still holds the context that produced them. The stress gate reruns the test cases a branch adds several times each, in a fresh process per repetition, and flags any that disagree with themselves before the change merges. Tuist decides what counts as new by checking which test cases have never run in CI on the project's default branch, so tests inherited from a base class, Swift Testing display names, parameterized cases, and annotation-driven discovery all count.

The gate is off unless you enable it, and it takes a mode rather than a switch so anyone reading the pipeline can see whether the job can fail on flakiness:

- **`report`**: prints a warning for each disagreement and exits on the first pass's own result. Start here and watch what the gate would have blocked for a couple of weeks.
- **`enforce`**: identical, but a disagreement fails the run with the same exit code as a failed test.

Pass the option ahead of the passthrough arguments, or set the `TUIST_TEST_STRESS_NEW_TESTS` environment variable to vary it per matrix lane:

```sh
tuist test --stress-new-tests report
```

Each new test case is rerun according to its own duration: up to 5 seconds earns 10 repetitions, up to 10 seconds 5, up to 30 seconds 3, up to 5 minutes 2, and slower test cases are excluded and reported as such. The pass reuses what the first pass built, is capped at 200 candidates and 10 minutes of wall-clock time, and every bound reports when it bites. The parameters are stored on the project and tuned by Tuist from telemetry, so they never require a CLI release.

The gate runs nothing, and says so, when the first pass already failed, when the project has no default branch or no CI history on it yet, or when more than 30% of the project's test inventory reads as new (a renamed module, for example). A branch that adds no tests prints nothing and costs one request. If the server cannot be reached, the run's own result stands: the gate never blocks a merge because Tuist was down.

Muted tests are stressed and recorded but cannot fail the gate, skipped tests never become candidates, and a test that fails the gate is never auto-quarantined. Repetitions the gate solicits are recorded apart from organic flakiness, so they never mark a test flaky, trigger alerts, or feed the flaky-test aggregates.

In the dashboard, every stressed test case is badged in the run's test case list. A test case that disagreed with itself is flaky, so it appears with the run's flaky tests, expandable to each repetition and the failure it produced. Opening any stressed test case run shows the same repetitions in full.

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
