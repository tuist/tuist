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

<HomeCards>
    <HomeCard
        icon="<img src='/images/guides/features/xcode-icon.png' alt='Xcode' width='32' height='32' />"
        title="Xcode"
        details="Detect, manage, and quarantine flaky tests in Xcode projects."
        linkText="Xcode flaky tests"
        link="/guides/features/test-insights/flaky-tests/xcode"/>
    <HomeCard
        icon="<img src='/images/guides/features/gradle-icon.svg' alt='Gradle' width='32' height='32' />"
        title="Gradle"
        details="Detect and manage flaky tests in Gradle projects."
        linkText="Gradle flaky tests"
        link="/guides/features/test-insights/flaky-tests/gradle"/>
</HomeCards>
