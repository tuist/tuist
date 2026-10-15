---
{
  "title": "Gradle Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track Gradle test analytics in the Tuist dashboard to monitor test performance."
}
---
# Gradle test insights {#gradle-test-insights}

Tuist's Gradle plugin automatically uploads test results after each test task execution, giving you visibility into test performance and flaky tests directly in the Tuist dashboard.

Test insights are collected automatically when the Tuist Gradle plugin is applied — no additional configuration is needed beyond the initial plugin setup.

You can access your test insights in the Tuist dashboard and see how they evolve over time:

![Dashboard with test insights](/images/guides/features/build-insights/tests-dashboard.png)

## What is tracked {#what-is-tracked}

The plugin collects results from all Gradle `Test` tasks, including:
- Individual test case pass/fail status and duration
- Test suite and class structure
- Flaky test detection across runs

## Configure upload behavior {#configure-upload-behavior}

By default:
- Test results are uploaded in the background for local builds.
- Test results are uploaded in the foreground for CI runs to avoid losing telemetry on short-lived agents.

You can override this behavior using `uploadInBackground` in the `tuist` block in your `settings.gradle.kts`:

```kotlin
tuist {
    uploadInBackground = false // always upload in the foreground
}
```

### Git history {#git-history}

On CI, the plugin also uploads the commit history of the checkout when it reports a test run: commit SHAs, their parents, commit dates, and the branch the run and its pull request's base branch were on. No file contents, commit messages, or authors are uploaded. It's what tells Tuist which commits landed on your default branch, for example the ones a merge queue tested. In a shallow clone, the plugin fetches the base branch and deepens the clone for a bounded time to find where the branch forked.

| Variable | Effect |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Doesn't read or upload any Git history. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | Reads only the history already in the checkout, without fetching. |
