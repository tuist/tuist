---
title: "Stop Flaky Tests from Blocking Your PRs"
category: "product"
tags: ["product", "test-insights"]
excerpt: "Flaky tests waste engineering hours and block PR throughput. Learn how Tuist automatically detects, tracks, and quarantines flaky tests so your team can ship faster."
author: fortmarek
og_image_path: /marketing/images/blog/2026/01/27/flaky-tests/og.jpg
highlighted: true
---

You open a pull request. The CI runs. It fails. You look at the failing test and it has nothing to do with your changes. You click retry. This time it passes. But now there's a merge conflict because someone else landed their changes while you were waiting. You resolve the conflict, push again, and the CI fails on a _different_ unrelated test. Another retry. Another wait. By the time your one-line fix actually lands, you've lost an hour to tests that aren't actually testing your code.

This scenario plays out thousands of times a day across engineering teams everywhere. And the worst part? Most organizations have no idea how much time they're losing. Flaky tests are a silent productivity killer that compounds over time, eroding trust in your test suite and frustrating developers who just want to ship their work.

## The hidden cost of flaky tests

The direct cost is easy to see: wasted CI minutes, wasted developer time, delayed merges. But the indirect cost is far more damaging.

When flaky tests become common, developers stop trusting the test suite. "It's probably just that flaky test" becomes the default assumption when CI fails. Real bugs slip through because the signal has been drowned out by noise. The test suite that was supposed to catch regressions before they reach production now gets ignored because it fails too often due to tests being unreliable.

And unlike a slow test suite or a missing feature, flaky tests are invisible in aggregate. No dashboard shows you "your team lost 47 hours this month to spurious failures." No alert fires when trust in your CI erodes past the point of usefulness. The cost accumulates silently until someone finally asks why PRs take so long to land.

## Why this matters more than ever

With the rise of AI coding agents like [Claude Code](https://claude.com/product/claude-code) and [Codex](https://openai.com/codex/), teams are producing more PRs than ever before. Agents can write code faster than humans, but they still have to wait for CI like everyone else. If your test suite is flaky, you've just created a bottleneck that scales with your agent usage. The more PRs you open, the more time gets wasted on spurious failures.

If your test suite is flaky, your PR throughput doesn't scale with your team. It becomes the bottleneck.

## Detecting flaky tests automatically

No developer should have to manually track which tests are unreliable. Flaky test detection builds on top of [Test Insights](https://docs.tuist.dev/en/guides/features/test-insights), so if you're already using it, you get flaky detection automatically. Tuist detects flaky tests in two ways:

### Retry-based detection

When you run tests with Xcode's retry functionality using `-retry-tests-on-failure` or `-test-iterations`, Tuist analyzes the results of each attempt. If a test fails on the first attempt but passes on the retry, Tuist automatically marks it as flaky.

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -retry-tests-on-failure \
  -test-iterations 3
```

This catches flakiness within a single CI run rather than needing multiple runs to detect it. We recommend enabling test retries if you haven't already.

### Cross-run detection

Even without retries, Tuist can detect flaky tests by comparing results across different CI runs on the same commit. If a test passes in one CI run but fails in another for the same commit SHA, both runs are marked as flaky.

This catches the particularly elusive flaky tests that don't fail consistently enough to be caught by retries but still cause intermittent CI failures that waste your team's time.

Once detected, flaky tests appear in your project's Flaky Tests page, where you can see the flakiness rate, track flaky runs over time, and drill into individual test cases.

![Flaky Tests page showing detected flaky tests with their flakiness rates](/marketing/images/blog/2026/01/27/flaky-tests/flaky-tests-page.png)

## Stop flaky tests from blocking your PRs

Knowing which tests are flaky doesn't help if they're still failing your CI. How do you keep shipping while you investigate and fix them?

This is where quarantining comes in. When you quarantine a test, you're marking it as "known flaky" and excluding it from your CI runs entirely. This prevents flaky failures from blocking your PRs while you work on a fix. You can enable automatic quarantine in your project's Automations settings so newly detected flaky tests are isolated immediately, or manually quarantine tests from the test case detail page when you want more control.

### Skipping quarantined tests

To actually skip quarantined tests in your CI, use the `tuist test case list` command with the `--skip-testing` flag:

```bash
xcodebuild test \
  -scheme MyScheme \
  $(tuist test case list --skip-testing)
```

This fetches all quarantined test identifiers and formats them as xcodebuild arguments. Your CI becomes reliable again, PRs stop getting blocked by unrelated failures, and your team stays productive while you fix the underlying issues.

Once you've shipped a fix, unmark the test as flaky from the test case detail page. If it becomes flaky again, Tuist will detect it and notify you.

## Stay informed with Slack notifications

You don't want to find out about flaky tests by having them block a critical PR. With the [Slack integration](https://docs.tuist.dev/en/guides/integrations/slack), you get notified the moment a test becomes flaky.

<img src="/marketing/images/blog/2026/01/27/flaky-tests/slack-alert.png" alt="Slack notification showing a new flaky test detected" style="max-width: 500px;" />

The notification includes direct links to investigate the flaky test case, so you can start debugging immediately rather than waiting until it blocks someone.

Additionally, when a PR has a flaky test run, it gets surfaced directly in the Tuist PR comment. The "Flaky Tests" section shows a summary of flaky tests per scheme with links to view all flaky runs without leaving your pull request.

![Flaky Tests in PR Comment](/marketing/images/blog/2026/01/27/flaky-tests/pr-comment.png)

## Getting started

To start detecting flaky tests, you need [Test Insights](https://docs.tuist.dev/en/guides/features/test-insights) configured for your project.

Once Test Insights is running:

1. Enable test retries in your CI with `-retry-tests-on-failure`
2. Update your CI to skip quarantined tests using `tuist test case list --skip-testing`
3. Set up [Slack alerts](https://docs.tuist.dev/en/guides/integrations/slack#flaky-test-alerts) to get notified when new flaky tests are detected

For detailed configuration options, see the [Flaky Tests documentation](https://docs.tuist.dev/en/guides/features/test-insights/flaky-tests).

## What's next

We're continuing to build on flaky test detection with features that further streamline your workflow:

- **Issue tracker integration**: When a new flaky test is detected, Tuist will be able to automatically create an issue in your tracker. When the issue is resolved, the test case gets unmarked as flaky, keeping everything in sync.
- **Sharding**: To further increase CI throughput, sharding lets you run your test suite across multiple machines in parallel. Since Tuist already knows the average duration of each test case, we can create balanced shards that all finish around the same time.

What would you like to see next? Reach out to us in our [community forum](https://community.tuist.dev) or send us an email at [contact@tuist.dev](mailto:contact@tuist.dev). Your feedback shapes what we build.

## Stop the cycle

Flaky tests don't just waste time. They erode trust in your test suite, slow down your release cycle, and compound developer frustration. Every retry is a context switch. Every false failure is a distraction from real work.

With automatic detection, quarantining, and notifications, Tuist turns flaky tests from an invisible drain on productivity into a visible, manageable problem. You can see exactly which tests are unreliable, stop them from blocking your PRs, and fix them on your own schedule rather than in the heat of a blocked deployment.

Your test suite should give you confidence, not anxiety. [Get on top of your flaky tests](https://docs.tuist.dev/en/guides/features/test-insights/flaky-tests) and stop wasting time on retries.
