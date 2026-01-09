---
title: "From reactive to proactive: Get Slack alerts for your build health"
category: "product"
tags: ["product", "integrations"]
excerpt: "Stop finding out about build regressions from frustrated teammates. Let Tuist notify you in Slack the moment something goes wrong."
author: fortmarek
og_image_path: /marketing/images/blog/2026/01/12/slack-integration/og.jpg
---

How does your team typically discover that build times have regressed? If you're like most teams, it goes something like this: a few days after a problematic change lands, engineers start complaining in Slack that builds feel slower. Someone eventually investigates, sifts through dozens of merged PRs, and tries to pinpoint which change caused the regression. Meanwhile, the entire team has been less productive—without anyone realizing it.

**But this scenario assumes you're tracking the data in the first place.** Many teams don't have any visibility into their build health at all. They run CI pipelines, but the only metrics they see are job durations—which bundle compilation, testing, and deployment into a single number. Build times, cache effectiveness, test performance? These remain invisible until the pain becomes undeniable.

For teams that do track metrics—whether through [Tuist Insights](https://docs.tuist.dev/en/guides/features/insights#insights) or other tooling—there's still a gap. Unless someone actively checks dashboards, regressions slip through unnoticed. The data exists, but it doesn't reach the people who need it when they need it.

**We think there's a better way.** Instead of waiting for problems to become obvious, what if your tools could surface issues the moment they happen?

## Bringing insights to where your team already works

With the new Slack integration, Tuist becomes proactive. Rather than requiring you to remember to check dashboards, it delivers the insights that matter directly to your Slack channels—where your team already communicates.

We've introduced two complementary features: **daily reports** and **alert rules**.

### Daily reports

Daily reports give your team a pulse check on project health without anyone having to lift a finger. Each morning (or whenever you configure), Tuist sends a summary to your chosen Slack channel with key metrics:

- Build duration trends
- Test duration trends
- Cache hit rate
- Selective test effectiveness
- Bundle size

<img src="/marketing/images/blog/2026/01/12/slack-integration/report.png" alt="A Slack report message showing build metrics with trend indicators" style="max-width: 500px;" />

Each metric includes a trend indicator showing how it compares to the previous period. Is your p90 build time creeping up? You'll see it immediately—not after engineers start grumbling about their workflow.

### Alert rules

While reports are great for staying informed, some regressions need immediate attention. Alert rules let you define thresholds that trigger notifications when something significant changes.

For example, you might configure an alert that fires when:
- The p90 build duration increases by more than 20% compared to the previous 100 builds
- The cache hit rate drops below a certain threshold
- Test duration increases by more than 15%

<img src="/marketing/images/blog/2026/01/12/slack-integration/alert.png" alt="A Slack alert notification showing a build time regression" style="max-width: 500px;" />

When an alert triggers, you get a Slack notification with the specific metric that regressed, the magnitude of the change, and links to investigate further. No more sifting through a week's worth of PRs to find the culprit—you'll know something went wrong within hours of the change landing.

A 24-hour cooldown prevents notification fatigue when a metric stays elevated, so you won't get spammed while investigating an issue.

## Why this matters

The cost of a build time regression isn't just the extra seconds or minutes each build takes. It's the compounding effect across your entire team, multiplied by every build they run, every day the regression goes undetected. A 20% build time increase that goes unnoticed for a week can translate to hours of lost productivity—and that's before accounting for the frustration and context-switching that slow builds cause.

Cache hit rate drops tell a similar story. A sudden drop often indicates unstable hashes—perhaps a PR introduced a dependency that changes on every build, invalidating caches for modules that depend on it. The sooner you catch this, the less compute you waste and the faster your CI pipelines run.

**Proactive monitoring turns unknown unknowns into known issues.** You can't fix problems you don't know about, and the longer they persist, the harder they become to diagnose.

## Getting started

If you're already using Tuist, adding Slack integration takes just a few minutes:

1. Connect your Slack workspace in the Integrations tab
2. Configure reports and alert rules in your project's notification settings

![The notifications settings page showing Slack configuration options](/marketing/images/blog/2026/01/12/slack-integration/notifications-settings.png)

For detailed setup instructions, including configuration options and on-premise installation, see the [Slack integration documentation](https://docs.tuist.dev/en/guides/integrations/slack).

## What's next

This is just the beginning of making Tuist more proactive. We're working on:

- **Email notifications** — not everyone lives in Slack, so we're adding the option to receive reports and alerts via email
- **Flaky test alerts** — as we build out flaky test detection, you'll be able to get notified when a flaky test is introduced, so you can address it before it starts causing spurious CI failures

We're also eager to hear from you. What other events would you want to be notified about? What metrics matter most to your team? Let us know in our [community forum](https://community.tuist.dev)—your feedback shapes what we build next.
