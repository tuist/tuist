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
> - Complete the <.localized_link href="/guides/get-started/elixir-project">shared Elixir setup</.localized_link> to report your test runs

![Flaky tests of a Phoenix application](/images/guides/features/elixir/flaky-tests.png)

## How flaky detection works {#how-it-works}

Tuist detects flaky tests in two ways:

### Test retries {#test-retries}

ExUnit runs every test once, so a test that fails intermittently looks the same as one that is broken. With retries enabled, the Hex package runs the tests that failed again, up to the number of times you set. A test that passes on a retry is reported as flaky, and the run succeeds if every failed test eventually passes.

Retries are off by default. Add `test_retries` to your existing Tuist options in `mix.exs` to enable them:

```elixir
tuist: [project: "account/project", cache: true, test_retries: 2]
```

Or for a single run, with a flag or an environment variable:

```bash
mix test --retries 2
TUIST_TEST_RETRIES=2 mix test
```

The flag takes precedence over the environment variable, and the environment variable over `mix.exs`.

Only the tests that failed run again, the way `mix test --failed` runs them, and the dashboard shows each attempt of a test and how long it took. A run that ExUnit stopped early because of `--max-failures` is not retried. A run whose failed tests all timed out is not retried either, since each retry would wait out every timeout again. Retries are also skipped with `--warnings-as-errors`, which `mix test` would no longer enforce, and from the root of an umbrella project; run the tests inside one of its applications to retry them.

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

## Quarantining flaky tests {#quarantining}

Quarantining keeps a flaky test from blocking CI while you fix it. On a test's page in the dashboard, change its state to **Muted** or **Skipped**, or configure an automation under **Settings → Automations** that mutes or skips a test when it becomes flaky and enables it again once it recovers. Before it runs the tests, `mix test` reads every quarantined test of the project and applies them:

- **Muted**: the test runs and its failure is still reported, but a run whose only failures are muted tests passes. Retries still rerun a failing muted test, so a flaky one can pass and be reported as flaky.
- **Skipped**: the test does not run. `mix test` lists the skipped tests before the run starts.

```text
Tuist: skipping 1 quarantined test:
  MyApp.CheckoutTest: create_order/2 times out
Tuist: 1 muted test run, and their failures do not fail the run.
```

The run fails as usual when any test that isn't muted fails, or when ExUnit stops early because of `--max-failures`.

> [!WARNING]
> **Limitations**
>
> - Only recent versions of the Hex package apply quarantine. Earlier versions run muted and skipped tests like any other, so a muted test's failure still fails the run. Update `tuist_ex` before you rely on it.
> - Muted tests are not applied with `--warnings-as-errors`, or from the root of an umbrella project. Their failures then fail the run. Run the tests inside each application of an umbrella instead.
> - A skipped test that isn't declared with `test`, such as a StreamData `property`, still runs.
> - On an Elixir version where `mix test` can't skip a test by its module, it skips by describe block and name instead: a test with the same describe block and name in another module is skipped too, and `--only`, `--include`, or `path:line` can select a skipped test. See [how skipping selects tests](#how-skipping-selects-tests).
> - If `mix test` cannot read the quarantined tests, it runs every test and counts every failure.
> - Reading the quarantined tests requires credentials, even for a public project. A run without a `TUIST_TOKEN`, a `mix tuist.login` session, or a continuous integration identity token applies no quarantine. That includes pull requests from forks, which usually run without secrets.
> - With `--cover`, a skipped test counts as removed: lines only it covered are reported as uncovered.
>
> `mix test` names the skipped tests that ran anyway, and any test a skip left out by mistake, after its summary.

### How skipping selects tests {#how-skipping-selects-tests}

A skipped test is left out by its module and its full name, such as `MyApp.CheckoutTest` and `test create_order/2 times out`. A test with the same describe block and name in another module still runs. A skipped test stays out even when you select it with `--only`, `--include`, or `path:line`. Pass `--no-quarantine` to run it.

ExUnit filters can't match a test's module and name together, so `mix test` adds that to ExUnit for the run, after it checks that your Elixir version works the way it expects. It has been verified on Elixir 1.18 to 1.20. Where it can't, it leaves a skipped test out with an ExUnit filter on its full name instead, such as `--exclude "test:test create_order/2 times out"`. Then:

- A test with the same describe block and name in another module is left out too. `mix test` names those tests after the run.
- A test you select with `--only`, `--include`, or `path:line` runs even when it is skipped, because ExUnit applies include filters after exclude filters. `mix test` names those tests after the run.

### Running quarantined tests again {#running-quarantined-tests-again}

Pass `--no-quarantine` to run every test and count every failure, for example to check a fix:

```bash
mix test --no-quarantine
```

Return the test to **Enabled** on its page to include it in later runs. A skipped test produces no new results until it runs again.

If `mix test` cannot read the quarantined tests, it prints a warning and runs every test without them. Without credentials or a configured project, it runs every test without a warning.

The Hex package does not stress-test new tests yet.

## Slack notifications {#slack-notifications}

Get notified instantly when a test becomes flaky by setting up <.localized_link href="/guides/integrations/slack#flaky-test-alerts">flaky test alerts</.localized_link> in your Slack integration.

## Querying flaky state {#querying}

The data is available over HTTP. See the [Test Cases endpoints](https://tuist.dev/api/docs#tag/test-cases) in the API reference for the full list of routes, filters, and response fields. To mark or unmark a test case as flaky, send `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}` with `is_flaky`, or use the `update_test_case` Model Context Protocol tool.
