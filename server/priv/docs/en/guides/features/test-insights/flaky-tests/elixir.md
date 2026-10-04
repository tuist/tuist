---
{
  "title": "Elixir Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect and manage flaky tests in Elixir projects built with Mix."
}
---
# Elixir flaky tests {#elixir-flaky-tests}

Flaky tests are tests that produce different results (pass or fail) when run multiple times with the same code. They erode trust in your test suite and waste developer time investigating false failures. Tuist automatically detects flaky tests and helps you track them over time.

> [!IMPORTANT] REQUIREMENTS
> - <.localized_link href="/guides/features/test-insights/elixir">Test insights</.localized_link> must be configured

![Flaky tests of a Phoenix application](/images/guides/features/elixir/flaky-tests.png)

## How flaky detection works {#how-it-works}

Tuist detects flaky tests in two ways:

### Test retries {#test-retries}

ExUnit runs every test once, so a test that fails intermittently looks the same as one that is broken. With retries enabled, the Hex package runs the tests that failed again, up to the number of times you set. A test that passes on a retry is reported as flaky, and the run succeeds if every failed test eventually passes.

Retries are off by default. Enable them for the whole project in your `mix.exs`:

```elixir
tuist: [project: "account/project", test_retries: 2]
```

Or for a single run, with a flag or an environment variable:

```bash
mix test --retries 2
TUIST_TEST_RETRIES=2 mix test
```

The flag takes precedence over the environment variable, and the environment variable over `mix.exs`.

Only the tests that failed run again, the way `mix test --failed` runs them, and the dashboard shows each attempt of a test and how long it took. A run that ExUnit stopped early because of `--max-failures` is not retried. Retries are also skipped with `--warnings-as-errors`, which `mix test` would no longer enforce, and from the root of an umbrella project; run the tests inside one of its applications to retry them.

![A flaky ExUnit test and its history](/images/guides/features/elixir/flaky-test-case.png)

### Cross-run detection {#cross-run-detection}

Even without test retries, Tuist can detect flaky tests by comparing results across different CI runs on the same commit. If a test passes in one CI run but fails in another run for the same commit, both runs are marked as flaky.

This is particularly useful for catching flaky tests that don't fail consistently enough to be caught by retries, but still cause intermittent CI failures.

## Managing flaky tests {#managing-flaky-tests}

### Automatic clearing

Detection and clearing run through an **automation alert** on the project. Every project gets a default "Flaky test detection" automation whose *trigger* marks a test as flaky and whose *recovery* clears the flag once the test has gone the configured recovery window (default **14 days**) without re-triggering. Edit it under **Settings → Automations** to change the recovery window or disable recovery entirely so tests stay marked flaky until you clear them by hand.

### Manual management

You can also manually mark or unmark tests as flaky from the test case detail page. This is useful when:
- You want to acknowledge a known flaky test while working on a fix
- A test was incorrectly flagged due to infrastructure issues

## Quarantining and stress-testing {#quarantining}

The Hex package does not apply quarantine yet: a test you mute or skip from the dashboard still runs with `mix test`, and its failure still fails the run. It does not stress-test new tests either. To keep a flaky test from blocking CI while you fix it, enable [test retries](#test-retries).

## Slack notifications {#slack-notifications}

Get notified instantly when a test becomes flaky by setting up <.localized_link href="/guides/integrations/slack#flaky-test-alerts">flaky test alerts</.localized_link> in your Slack integration.

## Querying flaky state {#querying}

The data is available over HTTP. See the [Test Cases endpoints](https://tuist.dev/api/docs#tag/test-cases) in the API reference for the full list of routes, filters, and response fields. State changes (mark or unmark flaky) currently happen from the dashboard, not through the public REST API.
