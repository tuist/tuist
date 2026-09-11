---
{
  "title": "Flaky Tests",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Automatically detect and track flaky tests in your CI pipelines."
}
---
# Flaky Tests {#flaky-tests}

> [!WARNING]
> **Requirements**
>
> - <.localized_link href="/guides/features/test-insights">Test Insights</.localized_link> must be configured


Flaky tests are tests that produce different results (pass or fail) when run multiple times with the same code. They erode trust in your test suite and waste developer time investigating false failures. Tuist automatically detects flaky tests and helps you track them over time.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Detect, manage, and quarantine flaky tests in Xcode projects via tuist xcodebuild test."
    link="/guides/features/test-insights/flaky-tests/xcode"
/>
  <.home_card
    title="Generated projects"
    details="Detect, manage, and quarantine flaky tests in Tuist generated projects via tuist test."
    link="/guides/features/test-insights/flaky-tests/generated-projects"
/>
  <.home_card
    title="Gradle"
    details="Detect and manage flaky tests in Gradle projects."
    link="/guides/features/test-insights/flaky-tests/gradle"
/>
  <.home_card
    title="Bazel"
    details="Detect, mute, and skip flaky Bazel test cases through tuist bazel test."
    link="/guides/features/test-insights/flaky-tests/bazel"
/>
</.home_cards>
