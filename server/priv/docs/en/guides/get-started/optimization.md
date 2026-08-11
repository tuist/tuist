---
{
  "title": "Optimize",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Reduce build and test times with caching, selective testing, and test sharding for Xcode and Gradle projects."
}
---
# Optimize {#optimize}

Reduce the time developers and automations spend waiting for builds and tests. Tuist can reuse build work, select only the tests affected by a change, and distribute longer test suites across multiple machines.

Optimization works best as a feedback loop. Begin by observing where developers and continuous integration spend the most time, make one targeted change, and compare the result with the original baseline. The <.localized_link href="/guides/get-started/observability">Observe path</.localized_link> explains how to connect build and test insights so you can identify the slowest stage and understand how each optimization affects the duration and reliability of your automation.

## Reuse build work {#reuse-build-work}

Most builds repeat work that another developer machine or continuous integration environment has already completed. Caching stores the result of that work and makes it available to later builds, which reduces compilation time without changing the build system your project already uses.

Start with the cache that matches your project:

- For an existing Xcode project or workspace, follow the <.localized_link href="/guides/get-started/existing-xcode-project">existing Xcode project guide</.localized_link> to enable compilation caching without adopting project generation.
- For a generated Xcode project, follow the <.localized_link href="/guides/get-started/generated-xcode-project">generated Xcode project guide</.localized_link> to use module caching or Xcode compilation caching.
- For a Gradle project, follow the <.localized_link href="/guides/get-started/gradle-project">Gradle project guide</.localized_link> to connect Gradle's build cache to Tuist.

Xcode compilation caching is useful when a team wants to keep an existing Xcode project or workspace, but it is generally less effective than Tuist's module cache. It reuses individual compilation outputs during the build, so Xcode still plans and executes the build around those cache hits.

The module cache, which Tuist enables through generated projects, replaces unchanged modules with prebuilt binaries before the build starts. This removes more compilation work and usually produces a larger and more predictable reduction in build time. Teams that can adopt project generation should start with the module cache, then combine it with Xcode compilation caching for work that cannot be reused at the module boundary.

The <.localized_link href="/guides/features/cache">cache overview</.localized_link> compares these approaches and explains how build work is shared between developer machines and continuous integration environments.

After enabling a cache, compare compilation duration and cache hit rates with the baseline. This shows whether the cache is removing the wait you intended to address and whether more of the build can be made reusable.

## Run fewer tests {#run-fewer-tests}

Running the complete test suite for every change provides broad coverage, but it also spends time on test targets that cannot be affected by the change. As a codebase grows, that repeated work can become a significant part of the feedback loop.

Use <.localized_link href="/guides/features/selective-testing">selective testing</.localized_link> to run only test targets affected by the changes since the last successful run. Tuist uses the project graph and the last successful result to determine which tests still need to run.

Selective testing is most effective when a typical change affects only part of the project. Observe the number of tests selected and the duration of the test stage before and after enabling it. This makes the time saved visible while preserving confidence that relevant tests continue to run.

## Run tests in parallel {#run-tests-in-parallel}

Even after removing unaffected tests, the required test suite may still take too long on one machine. <.localized_link href="/guides/features/test-sharding">Test sharding</.localized_link> distributes those tests across multiple machines and combines their results into one run.

Tuist uses historical test durations to create balanced shards. This is more effective than assigning the same number of tests to each machine because a small group of slow tests can otherwise hold back the entire automation.

Selective testing and test sharding solve different parts of the same problem. Selective testing reduces how much work is required, while sharding reduces how long the remaining work takes. Observe the duration of the slowest shard to decide whether adding more machines will produce a meaningful improvement.

## Choose an order {#choose-an-order}

Use a representative automation as the baseline, then address its longest wait:

1. Connect <.localized_link href="/guides/get-started/observability">build and test insights</.localized_link> to understand the current duration, failures, and slowest stages.
2. Add caching when compilation dominates the workflow.
3. Add selective testing when most test targets do not need to run for every change.
4. Add test sharding when the required tests remain too slow on one machine.

Run the same automation after each change and compare it with the baseline before adding the next optimization. This makes the impact clear, helps catch regressions, and shows where the next investment will save the most time.

These techniques compound over time. A workflow can reuse most of its build work, run only the tests affected by a change, and distribute those tests when they are still too slow for one machine. Observability keeps that system understandable as the project and the volume of code change continue to grow.
