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

When a test run gathers code coverage, Tuist reads the coverage Xcode writes into the result bundle, down to how many times each line ran, and stores it with the run. The dashboard then answers:

- What share of executable lines did this run cover?
- Which targets and files are poorly covered, and which lines and functions in them did no test reach?
- Is coverage trending up or down over time?

## Setup {#setup}

Coverage is reported whenever the result bundle contains it. Xcode gathers it when the scheme's test action has *Gather coverage* enabled, or when `xcodebuild` runs with `-enableCodeCoverage YES`.

If your scheme does not enable it, pass `--coverage` to `tuist xcodebuild test` or `tuist test` and Tuist adds the flag for you:

```bash
tuist xcodebuild test --coverage -workspace App.xcworkspace -scheme App -destination 'platform=iOS Simulator,name=iPhone 16'
```

The same works with the `TUIST_TEST_COVERAGE=1` environment variable. A `-enableCodeCoverage` argument you pass yourself always wins.

> [!NOTE]
> Coverage is read from the result bundle, so it works with every way of reporting a run: `tuist xcodebuild test`, `tuist test`, and the `tuist inspect test` scheme post-action.

## How it is processed {#how-it-is-processed}

When Tuist processes the result bundle on the server, which is the default for Tuist-hosted projects, the server reads the coverage with `xccov`. The CLI only adds a small manifest to the uploaded bundle: the repository's root directory and the [Git blob id](https://git-scm.com/book/en/v2/Git-Internals-Git-Objects) of each tracked source file, which only your checkout knows. When the CLI processes the bundle itself, it reads the coverage with the same parser and sends it with the run.

## What is stored {#what-is-stored}

For every source file the run's instrumented binaries compiled, Tuist stores its path relative to the repository's root, its Git blob id, the targets that compiled it, how many times each executable line ran, and its functions with their execution counts and coverage.

A source file linked into several targets, such as a framework's file and the test bundle that links the framework, counts towards each of them in the per-target view. The run's total counts each file once, so it can be lower than the sum of the targets, and lower than the figure Xcode's report navigator shows.

For a run split into shards, the shards' lines are combined: a line counts as covered when any shard ran it.

## Runs that skip tests {#runs-that-skip-tests}

A run that leaves tests out on purpose, through <.localized_link href="/guides/features/selective-testing">selective testing</.localized_link>, `-only-testing`, or `-skip-testing`, does not run every test that covers its files. Xcode still builds the skipped tests' targets, so their sources show up with the lines only the skipped tests reach left uncovered, or do not show up at all. Reporting what the run observed alone would make coverage drop every time tests are skipped.

Instead, for every source file of such a run, Tuist looks for the latest run in the last 30 days that observed the same file with the same Git blob id, and counts the lines that run covered as covered. The run's **Line coverage** includes that evidence; the **Observed coverage** widget shows the figure without it, and the files table marks the files whose coverage includes it. A file whose contents changed never takes earlier coverage.

## Dashboard {#dashboard}

Open a test run and select the **Coverage** tab to see the run's line coverage, its targets, and its files sorted from least to most covered. Select a file to see its uncovered lines and its functions.

The tests overview shows the **Line coverage** widget: the share of executable lines covered across the runs in the selected period that gathered coverage, with its trend against the previous period and a chart over time. Runs without coverage are left out of the figure rather than dragging it down.

## Limitations {#limitations}

- Coverage is recorded per run. Which test covered which line is not recorded yet.
- Partial-line coverage (a line whose branches only some tests took) is not stored; a line counts as covered when it ran at all.
- Files outside the repository, such as package checkouts in derived data, are stored with their absolute path and no Git blob id, so they are never carried forward.
