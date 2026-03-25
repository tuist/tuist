---
title: "Run your Test Suite Across Balanced Shards"
category: "product"
tags: ["product", "test-sharding", "test-insights", "ci"]
excerpt: "When parallelizing tests on a single machine isn't enough, sharding across multiple CI runners is the next step. Tuist uses historical timing data to create dynamically balanced shards so every runner finishes at the same time."
author: fortmarek
og_image_path: /marketing/images/blog/2026/03/25/test-sharding/og.jpg
highlighted: true
---

As your project grows, so does your test suite, and soon your test suite is taking 20 minutes or even longer, significantly slowing down all engineers at your company. You've already enabled parallel testing, maxed out your CI runner's cores, and there's nothing left to squeeze out of a single machine. The simulator count is the bottleneck, or the CPU just can't keep up. You're stuck.

This is the point where most teams start accepting slow CI as a fact of life. PRs queue up, developers context-switch while waiting, and the feedback loop that's supposed to catch bugs before they ship stretches into something that actively slows down shipping. With AI coding agents producing more PRs than ever, this bottleneck only gets worse.

The answer is straightforward: run your tests on multiple machines in parallel, also known as sharding. But _how_ you shard matters.

## The sharding problem

The naive approach is to split tests statically. You decide upfront which tests go where: modules A and B on shard 1, modules C and D on shard 2, and so on. It works at first. But test suites aren't static. New tests get added, old ones get refactored, and execution times shift. What was a balanced split last month becomes lopsided today. One shard finishes in 3 minutes while another takes 12. Your CI workflow is only as fast as the slowest shard, so you're waiting on that one overloaded runner while the others sit idle.

Keeping static shards balanced is a maintenance burden that scales with your test suite. Every time the distribution drifts, someone has to manually rebalance. In practice, nobody does until the pain is bad enough to complain about.

![Comparison of no sharding (20 min), static sharding (14 min bottleneck), and dynamic sharding (7 min balanced) across 3 shards](/marketing/images/blog/2026/03/25/test-sharding/sharding-comparison.png)

Dynamic sharding solves this. Instead of hardcoding the split, you let the system decide how to distribute tests based on how long each one actually takes. Every time you shard, the distribution is recalculated from real data. No manual tuning, no drift, no maintenance.

## Why Tuist is uniquely positioned

If you're already using [Test Insights](https://docs.tuist.dev/en/guides/features/test-insights), Tuist knows exactly how long every test module and test suite takes to run. We've been collecting this data for months. So when it's time to shard, we don't guess. We use a [bin-packing algorithm](https://en.wikipedia.org/wiki/Bin_packing_problem) that takes historical test durations and assigns tests to shards so each shard runs for roughly the same amount of time.

The algorithm is greedy LPT (Longest Processing Time first): sort all test units by their average duration in descending order, then assign each one to whichever shard currently has the lowest total duration. The result is a balanced distribution that adapts automatically as your test suite evolves.

For tests without historical data (new tests, for example), we estimate their duration using the median of known tests. No manual configuration needed.

## How it works

Test sharding follows a two-phase workflow:

1. **Build phase:** A single CI runner builds the tests, enumerates the test modules (or suites), and sends that list to the Tuist server. The server creates a shard plan using historical timing data and returns a matrix that your CI uses to spawn parallel runners.
2. **Test phase:** Each runner receives a shard index, downloads the pre-built test artifacts, and executes only the tests assigned to its shard. Results are uploaded to Tuist and merged into a single unified view in [Test Insights](https://docs.tuist.dev/en/guides/features/test-insights).

The build happens once. Only the test execution is parallelized. This means you're not wasting CI minutes compiling the same code on every shard.

## Getting started

Here's how test sharding looks on GitHub Actions with `tuist xcodebuild`:

```yaml
# GitHub Actions
jobs:
  build:
    runs-on: macos-latest
    outputs:
      matrix: ${{ steps.build.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - id: build
        run: |
          tuist xcodebuild build-for-testing \
            -scheme MyScheme \
            -destination 'platform=iOS Simulator,name=iPhone 16' \
            --shard-total 5

  test:
    needs: build
    runs-on: macos-latest
    strategy:
      fail-fast: false
      matrix:
        shard: ${{ fromJson(needs.build.outputs.matrix).shard }}
    env:
      TUIST_SHARD_INDEX: ${{ matrix.shard }}
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - run: |
          tuist xcodebuild test \
            -scheme MyScheme \
            -destination 'platform=iOS Simulator,name=iPhone 16'
```

You can use `--shard-total` for a fixed number of shards, or `--shard-min` / `--shard-max` with `--shard-max-duration` to let Tuist determine the optimal shard count automatically based on your timing data. For finer-grained balancing, set `--shard-granularity suite` to distribute individual test classes instead of entire modules.

Test sharding also works with [Tuist generated projects](https://docs.tuist.dev/en/guides/features/test-sharding/generated-projects) via `tuist test` (including seamless [selective testing](https://docs.tuist.dev/en/guides/features/selective-testing) support) and [Gradle projects](https://docs.tuist.dev/en/guides/features/test-sharding/gradle) via the Tuist Gradle plugin. See the [test sharding documentation](https://docs.tuist.dev/en/guides/features/test-sharding) for full setup details.

## Unified results

Regardless of how many shards you run, the results are merged into a single test run in [Test Insights](https://docs.tuist.dev/en/guides/features/test-insights). You see one unified view of your test suite with shard balance visualization, per-shard duration, and bottleneck identification. No stitching logs together from multiple runners. No spreadsheets. Just one dashboard.

## Stop waiting

Your test suite will keep growing. The question is whether your CI grows with it or becomes the bottleneck. Static sharding is a temporary fix that creates its own maintenance burden. Dynamic sharding adapts automatically, stays balanced, and requires no ongoing tuning.

If you're already using Test Insights, you have everything you need. The timing data is already there. [Set up test sharding](https://docs.tuist.dev/en/guides/features/test-sharding) and stop waiting on a single machine.

Have questions or feedback? Reach out in our [community forum](https://community.tuist.dev) or send us an email at [contact@tuist.dev](mailto:contact@tuist.dev).
