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
> - Complete <.localized_link href="/guides/get-started/elixir-project">Get started with Elixir</.localized_link>

## Report your test runs {#report-your-test-runs}

The shared setup installs the test integration. Keep using `mix test`, with the same arguments, output and exit code:

```bash
mix test test/my_app_test.exs:12 --trace
```

Tuist reports the run when it finishes; no additional test alias is needed.

You can access your test insights in the Tuist dashboard and see how they evolve over time:

![Tests dashboard of a Phoenix application](/images/guides/features/elixir/tests-dashboard.png)

## What is tracked {#what-is-tracked}

The package collects results from ExUnit, including:
- Individual test pass/fail status and duration
- The module and `describe` block each test belongs to
- The message and location of each failure
- Flaky test detection across runs
- The branch and commit, and on continuous integration, the provider and the run
- On continuous integration, the [Git history](#git-history) of the checkout

Doctests are reported like any other test. With `--cover`, the run's line coverage is uploaded too: see <.localized_link href="/guides/features/test-code-coverage/elixir">Elixir code coverage</.localized_link>.

> [!NOTE]
> The package reports through an ExUnit formatter that it adds next to the ones you already use. If you pass `--formatter` on the command line, Mix replaces the whole list, so the run is not reported and the task warns you about it.

### Git history {#git-history}

On continuous integration, the package also uploads the commit history of the checkout: commit SHAs, their parents, commit dates, and the branch the run and its pull request's base branch were on. No file contents, commit messages, or authors are uploaded. It's what tells Tuist which commits landed on your default branch, for example the ones a merge queue tested. The package reads the history the checkout already has, and when the checkout doesn't have the base branch, asks the remote for its latest commit (`git ls-remote`). Outside code coverage (`--cover`), it doesn't fetch history.

| Variable | Effect |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Doesn't read or upload any Git history. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | Reads only the checkout, without contacting the remote. |

## Troubleshooting {#troubleshooting}

Reporting never changes the result of your tests: if the report cannot be sent, the run exits as it would have and nothing is printed. To see why a report was not sent, set `TUIST_DEBUG=1`:

```bash
TUIST_DEBUG=1 mix test
```
