---
{
  "title": "Code coverage",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track the line coverage of your Xcode test runs and find the files your tests never reach."
}
---
# Code coverage {#code-coverage}

> [!WARNING]
> **Requirements**
>
> - A <.localized_link href="/guides/server/accounts-and-projects">Tuist account and project</.localized_link>
> - Xcode test runs reported through <.localized_link href="/guides/features/test-insights/xcode">Test Insights</.localized_link>

When a test run gathers code coverage, Tuist reads the coverage report Xcode writes into the result bundle and stores it with the run. The dashboard then answers:

- What share of executable lines did this run cover?
- Which targets and files are poorly covered?
- Is coverage trending up or down over time?

## Setup {#setup}

Coverage is reported whenever the result bundle contains it. Xcode gathers it when the scheme's test action has *Gather coverage* enabled, or when `xcodebuild` runs with `-enableCodeCoverage YES`.

If your scheme does not enable it, pass `--coverage` to `tuist xcodebuild test` or `tuist test` and Tuist adds the flag for you:

```bash
tuist xcodebuild test --coverage -workspace App.xcworkspace -scheme App -destination 'platform=iOS Simulator,name=iPhone 16'
```

The same works with the `TUIST_TEST_COVERAGE=1` environment variable. A `-enableCodeCoverage` argument you pass yourself always wins.

> [!NOTE]
> Coverage is read from the result bundle with `xccov`, so it works with every way of reporting a run: `tuist xcodebuild test`, `tuist test`, and the `tuist inspect test` scheme post-action.

## What is stored {#what-is-stored}

Tuist stores what `xccov` reports: every target the scheme gathered coverage for, and each source file compiled into it with its covered and executable line counts. Files under the project's root directory are stored with a path relative to it.

A source file linked into several targets, such as a framework's file and the test bundle that links the framework, appears under each of them in the per-target view. The run's total counts each file once, so it can be lower than the sum of the targets, and lower than the figure Xcode's report navigator shows.

## Dashboard {#dashboard}

Open a test run and select the **Coverage** tab to see the run's line coverage, its targets, and its files sorted from least to most covered.

The tests overview shows the **Line coverage** widget: the share of executable lines covered across the runs in the selected period that gathered coverage, with its trend against the previous period and a chart over time. Runs without coverage are left out of the figure rather than dragging it down.

## Limitations {#limitations}

- Coverage is aggregated per run. Which test covered which line is not recorded yet.
- Line-level execution counts and function coverage are not stored; the file's covered and executable line counts are.
- For a run split into shards, each shard reports the files it covered and a file keeps the highest count any shard observed.
