---
{
  "title": "Elixir Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track the tests of your Elixir project in the Tuist dashboard to monitor test performance."
}
---
# Elixir test insights {#elixir-test-insights}

Tuist's Hex package uploads the test results of your Elixir project after each test run, giving you visibility into test performance and flaky tests directly in the Tuist dashboard.

> [!IMPORTANT] REQUIREMENTS
> - The <.localized_link href="/guides/install-hex-package">Hex package</.localized_link> installed and configured

## Report your test runs {#report-your-test-runs}

Run `mix tuist.test` instead of `mix test`. It takes the same arguments and reports the run when it finishes:

```bash
mix tuist.test test/my_app_test.exs:12 --trace
```

To report every run without anyone having to remember a different command, alias it in your `mix.exs`:

```elixir
def project do
  [
    app: :my_app,
    aliases: [test: "tuist.test"],
    tuist: [project: "account/project"]
  ]
end
```

`mix test` then runs and reports exactly as `mix tuist.test` would, with the same output and the same exit code.

You can access your test insights in the Tuist dashboard and see how they evolve over time:

![Tests dashboard of a Phoenix application](/images/guides/features/elixir/tests-dashboard.png)

## What is tracked {#what-is-tracked}

The package collects results from ExUnit, including:
- Individual test pass/fail status and duration
- The module and `describe` block each test belongs to
- The message and location of each failure
- Flaky test detection across runs
- The branch and commit, and on continuous integration, the provider and the run

Doctests are reported like any other test.

> [!NOTE]
> The package reports through an ExUnit formatter that it adds next to the ones you already use. If you pass `--formatter` on the command line, Mix replaces the whole list, so the run is not reported and the task warns you about it.

## Troubleshooting {#troubleshooting}

Reporting never changes the result of your tests: if the report cannot be sent, the run exits as it would have and nothing is printed. To see why a report was not sent, set `TUIST_DEBUG=1`:

```bash
TUIST_DEBUG=1 mix test
```
