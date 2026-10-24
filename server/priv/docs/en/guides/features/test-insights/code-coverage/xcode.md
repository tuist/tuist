---
{
  "title": "Xcode Code Coverage",
  "titleTemplate": ":title · Code Coverage · Test Insights · Features · Guides · Tuist",
  "description": "Upload the code coverage of Xcode projects to Tuist and follow it per file and per commit."
}
---
# Xcode code coverage {#xcode-code-coverage}

> [!WARNING]
> **Requirements**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Xcode test insights</.localized_link> configured. Tuist uploads a run's coverage along with its test results.

> [!NOTE] EARLY ACCESS
> Code coverage is in early access. [Reach out](mailto:contact@tuist.dev) to turn it on for your account, and set `TUIST_FEATURE_FLAG_COVERAGE=1` wherever you run Tuist, on CI and on developers' machines. Without the variable, Tuist collects and uploads no coverage.

Code coverage tells you which lines of your code your tests executed. Tuist uploads the line coverage of every test run and folds the runs of a commit into one figure, for the project, each target and each file. The dashboard's **Code Coverage** page shows it per commit and as a trend for each branch.

> [!TIP]
> If you generate your project with Tuist, follow the <.localized_link href="/guides/features/test-insights/code-coverage/generated-xcode-project">generated project guide</.localized_link> instead: it measures the code that comes from the binary cache and carries forward the coverage of the tests selective testing skips.

## Setup {#setup}

### Collect coverage {#collect-coverage}

Turn on **Code Coverage** in your scheme's test action (**Edit Scheme › Test › Options**), or pass `-enableCodeCoverage YES` to the run. Then run your tests through `tuist xcodebuild test`:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -enableCodeCoverage YES
```

Tuist uploads the coverage the run collected along with its test results. To upload test runs without their coverage, turn the upload off in `Tuist.swift`, or set `TUIST_COVERAGE_UPLOAD=0` for a single environment:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "my-account/my-project",
    testInsights: .testInsights(coverage: .coverage(upload: false)),
    project: .xcode()
)
```

### Complete each commit on CI {#complete-each-commit}

A commit's coverage often comes from several jobs: one per scheme, per shard, or per platform. Tuist can't tell when the last of them has reported, so tell it. Once every test job for a commit has finished, run this in a job that depends on all of them:

```sh
tuist coverage complete
```

Until a commit is complete, its coverage shows as **In progress** and stays out of its branch's trend. The <.localized_link href="/guides/features/test-insights/code-coverage/generated-xcode-project#commit-status">generated project guide</.localized_link> describes each status.

## Skipped tests {#skipped-tests}

When a run skips tests with `-skip-testing`, it measures less than the commit's tests cover, and the commit's coverage is **Incomplete**. Tuist can fill in those tests with the coverage they had in an earlier run, in which they executed the same files, when you record test-level coverage:

- Add the [TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) package to your project and add its `TestCoverageAttribution` library to your unit test targets' **Link Binary With Libraries** phase. Never link it to an app target.
- Add the `.coverageAttribution` trait to your Swift Testing suites. XCTest tests need nothing else.
- Set `TUIST_COVERAGE_EVIDENCE=1` wherever your tests run, while test-level coverage is in early access.

Tests that quarantine skips aren't part of the coverage at all, so they never make a commit **Incomplete**.

Swift Testing tests that run in parallel can't be attributed one by one. See <.localized_link href="/guides/features/test-insights/code-coverage/generated-xcode-project#test-level-coverage">test-level coverage</.localized_link> for the trait and its limitations.

## Performance impact {#performance-impact}

Collecting coverage makes a run longer mainly after the tests finish, while Xcode writes its coverage report and Tuist exports the coverage. On Tuist's own repository that took about 16 seconds of an 11-minute run, with no measurable change in build or test execution time. See <.localized_link href="/guides/features/test-insights/code-coverage/generated-xcode-project#performance-impact">performance impact</.localized_link> for the details.

## Querying coverage {#querying}

The `tuist coverage` commands read what the dashboard shows. Without `--commit`, they read the latest complete commit of `--branch`, or of your default branch:

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
```

All of them accept `--json` for scripting.
