---
{
  "title": "Observe",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Understand build and test performance, failures, flaky behavior, and regressions across Xcode and Gradle projects."
}
---
# Observe {#observe}

Turn build and test runs into information your team can act on. Tuist collects performance and result data across developer machines and continuous integration environments so you can find regressions, failures, and flaky behavior.

Observation gives the team a shared baseline before it changes the workflow. A single run can show that an automation was slow or failed, but a sequence of comparable runs reveals whether that result is typical, where time is being spent, and when behavior started to change.

Begin with a representative build and test workflow that developers run frequently. Capture several runs from developer machines and continuous integration because machine load, cache state, and the size of a change can all affect duration. Look for patterns across those runs instead of using the fastest result as the baseline.

## Understand builds {#understand-builds}

<.localized_link href="/guides/features/build-insights">Build insights</.localized_link> show duration trends and the work performed by each build. They help turn a general report that builds feel slow into questions the team can answer:

- Did build duration change after a particular change to the project?
- Does the slowdown affect developer machines, continuous integration, or both?
- Is the build consistently slow, or is the result limited to a small number of runs?

Connect the guide that matches the build system already used by the project:

- For an existing Xcode project or workspace, follow the <.localized_link href="/guides/features/build-insights/xcode">Xcode build insights guide</.localized_link>.
- For a generated Xcode project, follow the <.localized_link href="/guides/features/build-insights/generated-projects">generated project build insights guide</.localized_link>.
- For a Gradle project, follow the <.localized_link href="/guides/features/build-insights/gradle">Gradle build insights guide</.localized_link>.

Once builds appear in the dashboard, compare runs that perform similar work. A clean build and an incremental build answer different questions, just as a small source change and a dependency update create different workloads. Keeping those comparisons focused makes a regression easier to identify and explain.

## Understand tests {#understand-tests}

The total duration of a test run tells you when feedback arrived, but it does not explain what delayed it. <.localized_link href="/guides/features/test-insights">Test insights</.localized_link> show test duration, failures, and reliability so you can understand whether time is spread across the suite or concentrated in a smaller group of tests.

Connect test insights through the guide for your project:

- For Xcode projects, follow the <.localized_link href="/guides/features/test-insights/xcode">Xcode test insights guide</.localized_link>.
- For Gradle projects, follow the <.localized_link href="/guides/features/test-insights/gradle">Gradle test insights guide</.localized_link>.
- Use <.localized_link href="/guides/features/test-insights/flaky-tests">flaky test detection</.localized_link> to identify tests whose results change without a corresponding code change.

Not every test failure has the same cause. A test that fails consistently after a source change can point to a regression, while a test whose result changes without a corresponding code change can interrupt the workflow without providing useful feedback. Looking at results over time helps the team separate these cases and decide whether to fix product behavior, improve the test, or investigate the environment.

Duration trends also show which tests dominate the critical path. This becomes important when deciding whether to run fewer tests or distribute the required tests across more machines.

## Verify the data {#verify-the-data}

Useful comparisons depend on complete and consistent data. Run one representative build and test workflow, then open the Tuist dashboard and confirm that:

1. The build appears with its duration and build-system details.
2. The test run lists the executed tests, their duration, and their results.
3. Runs from developer machines and continuous integration use the same Tuist project.

Repeat the workflow from both a developer machine and continuous integration. Confirm that each run appears where the team expects it and that the recorded result matches what happened in the automation. If the two environments behave differently, keep that distinction visible instead of combining them into one baseline.

Once data is flowing consistently, observe several representative runs before changing the workflow. This gives the team enough context to distinguish a lasting improvement from the normal variation between runs.

## Measure improvements {#measure-improvements}

With a baseline in place, follow the <.localized_link href="/guides/get-started/optimization">Optimize path</.localized_link> to address the longest wait. Apply one change at a time, then run the same automation again and compare it with the original baseline.

Use the comparison to answer:

- Did the total duration improve?
- Did the change remove the intended bottleneck, or move the wait to another stage?
- Is the improvement visible on both developer machines and continuous integration?
- Did reliability remain stable while the workflow became faster?

Evaluate several comparable runs before deciding that an optimization worked. Continue observing after the change is adopted so the team can detect regressions as the project, test suite, and volume of code changes grow.
