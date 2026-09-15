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

Tuist uploads the coverage of every test run whose result bundle contains it. You enable coverage the way Xcode expects, and nothing else is needed.

For projects generated with Tuist, enable it in the scheme's test action:

```swift
.scheme(
    name: "App",
    testAction: .targets(["AppTests"], options: .options(coverage: true, codeCoverageTargets: ["App"]))
)
```

or for automatically generated schemes:

```swift
let project = Project(
    name: "App",
    options: .options(automaticSchemesOptions: .enabled(codeCoverageEnabled: true)),
    targets: [...]
)
```

Then run your tests as usual, locally and on CI:

```bash
tuist test App
```

For other projects, tick *Gather coverage* in the scheme's test options, or pass `-enableCodeCoverage YES`:

```bash
tuist xcodebuild test -workspace App.xcworkspace -scheme App -destination 'platform=iOS Simulator,name=iPhone 16' -enableCodeCoverage YES
```

Runs reported through the `tuist inspect test` scheme post-action include coverage in the same way.

### Opting out of the upload {#opting-out}

To upload test runs without their coverage, for example when coverage must not leave your machines, set it in `Tuist.swift`:

```swift
let tuist = Tuist(
    fullHandle: "org/app",
    testInsights: .testInsights(coverage: .coverage(upload: false)),
    project: .tuist()
)
```

The `TUIST_COVERAGE_UPLOAD` environment variable takes precedence over this setting, so a single run or CI job can opt out (`TUIST_COVERAGE_UPLOAD=0`) or back in (`TUIST_COVERAGE_UPLOAD=1`). Xcode still gathers coverage either way.

## How it is processed {#how-it-is-processed}

When Tuist processes the result bundle on the server, which is the default for Tuist-hosted projects, the server reads the coverage with `xccov`. The CLI only adds a small manifest to the uploaded bundle: the repository's root directory and the <a href="https://git-scm.com/book/en/v2/Git-Internals-Git-Objects">Git blob id</a> of each covered file, which only your checkout knows. When the CLI processes the bundle itself, it reads the coverage with the same parser and sends it with the run.

## What is stored {#what-is-stored}

For every source file the run's instrumented binaries compiled, Tuist stores its path relative to the repository's root, its Git blob id, the targets that compiled it, how many times each executable line ran, and its functions with their execution counts and coverage.

A source file linked into several targets, such as a framework's file and the test bundle that links the framework, counts towards each of them in the per-target view. The run's total counts each file once, so it can be lower than the sum of the targets, and lower than the figure Xcode's report navigator shows.

For a run split into shards, the shards' lines are combined: a line counts as covered when any shard ran it.

## Runs that skip tests {#runs-that-skip-tests}

A run that leaves tests out on purpose, through <.localized_link href="/guides/features/selective-testing">selective testing</.localized_link>, `-only-testing`, or `-skip-testing`, only measures the tests that ran. Tuist marks its coverage as partial on the run page and leaves it out of the coverage trend, so skipped tests never make coverage look lower than it is.

To track your project's coverage over time, gather coverage on runs that execute every test, for example on your default branch.

## Dashboard {#dashboard}

Open a test run and select the **Coverage** tab to see the run's line coverage, its targets, and its files sorted from least to most covered. Select a file to see its uncovered lines and its functions.

The tests overview shows the **Line coverage** widget: the share of executable lines covered across the runs in the selected period that gathered coverage and ran every test, with its trend against the previous period and a chart over time. Runs without coverage are left out of the figure rather than dragging it down.

## Limitations {#limitations}

- Coverage is recorded per run. Which test covered which line is not recorded yet.
- Partial-line coverage (a line whose branches only some tests took) is not stored; a line counts as covered when it ran at all.
- Files outside the repository, such as package checkouts in derived data, are stored with their absolute path and no Git blob id.
- A run that skips tests does not borrow coverage from earlier runs, so its figure is lower than the project's.
