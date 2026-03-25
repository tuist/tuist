---
title: "Run your test suite across balanced shards"
category: "product"
tags: ["product", "test-sharding", "test-insights", "ci"]
excerpt: "When parallelizing tests on a single machine isn't enough, sharding across multiple CI runners is the next step. Tuist uses historical timing data to create dynamically balanced shards so every runner finishes roughly at the same time."
author: fortmarek
og_image_path: /marketing/images/blog/2026/03/25/test-sharding/og.jpg
highlighted: true
---

As your project grows, your test suite execution time does, too. You've already enabled parallel testing, maxed out your CI runner's cores, and there's nothing left to squeeze out of a single machine. The simulator count is the bottleneck, or maybe the CPU just can't keep up.

This is when most teams reach for the obvious solution: run tests on multiple machines in parallel, also known as sharding. But _how_ you shard matters and this is where Tuist's new sharding becomes really useful.

## The sharding problem

The naive approach is to split tests statically. You decide upfront which tests go where: modules A and B on shard 1, modules C and D on shard 2, and so on. It works at first, but your codebase isn't static. What was a balanced split last month becomes lopsided today, with one shard finishing in 3 minutes while another takes 12. Your CI workflow is only as fast as the slowest shard, so you're waiting on that one overloaded runner while the others sit idle.

Keeping static shards balanced is a maintenance burden that scales with your test suite. Every time the distribution drifts, someone has to manually rebalance. In practice, nobody does until the pain is bad enough to complain about.

<img src="/marketing/images/blog/2026/03/25/test-sharding/sharding-comparison.png" alt="Comparison of no sharding (20 min), static sharding (14 min bottleneck), and dynamic sharding (7 min balanced) across 3 shards" style="max-height: 500px;" />

Dynamic sharding solves this. Instead of hardcoding the split, you let the system decide how to distribute tests based on how long each one actually takes. Every time you shard, the distribution is recalculated from real data, without you having to constantly balance the shards manually.

## Leveraging test insights

For optimal sharding, we leverage our [Test Insights](https://tuist.dev/test-insights) to know exactly how long every test module and test suite typically takes to run. So when it's time to shard, we use a [bin-packing algorithm](https://en.wikipedia.org/wiki/Bin_packing_problem) that takes historical test durations and assigns tests to shards so each shard runs for roughly the same amount of time.

The algorithm is greedy LPT (Longest Processing Time first): sort all test units by their average duration in descending order, then assign each one to whichever shard currently has the lowest total duration. The result is a balanced distribution that adapts automatically as your test suite evolves.

For tests without historical data (new tests, for example), we estimate their duration using the median of known tests.

## How it works

Test sharding follows a two-phase workflow:

1. **Build phase:** A single CI runner builds the tests and uploads the test artifacts (`.xctestproducts` for Xcode and compiled test classes for Gradle) to the Tuist server. The server then creates a shard plan using historical timing data and returns a matrix that your CI uses to spawn parallel runners.
2. **Test phase:** Each runner receives a shard index, downloads the pre-built test artifacts, and executes only the tests assigned to its shard. Results are uploaded to Tuist and merged into a single unified view in our dashboard.

This split also opens the door to CI cost savings. The build phase is CPU-intensive and benefits from a beefy machine, but the shard runners only execute pre-built tests. For workloads like UI tests where the CPU isn't the bottleneck, you can use cheaper, less powerful runners for the test phase without affecting execution speed.

## Getting started

Here's how an example test sharding workflow looks on GitHub Actions with `tuist xcodebuild`:

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

Test sharding also works with [Tuist generated projects](https://docs.tuist.dev/en/guides/features/test-sharding/generated-projects) via `tuist test` (including seamless [selective testing](https://docs.tuist.dev/en/guides/features/selective-testing) support) and [Gradle projects](https://docs.tuist.dev/en/guides/features/test-sharding/gradle) using the Tuist Gradle plugin. See the [test sharding documentation](https://docs.tuist.dev/en/guides/features/test-sharding) for full setup details.

## Stop waiting

Your test suite will keep growing, now more than ever. The question is whether your CI grows with it or becomes the bottleneck. Static sharding is a temporary fix that creates its own maintenance burden, while Tuist's dynamic sharding adapts automatically, stays balanced, and seamlessly integrates with other features, like test insights.

Have questions or feedback? Reach out in our [community forum](https://community.tuist.dev) or send us an email at [contact@tuist.dev](mailto:contact@tuist.dev).
