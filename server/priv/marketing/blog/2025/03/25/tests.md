---
title: "Optimize your Swift test suite to run faster"
category: "learn"
tags: ["ci", "automation"]
excerpt: "Slow test suites drag your team down. Learn how to speed up your Swift tests effectively."
author: pepicrft
---

When projects kick off and establish their workflows, developers typically define processes that can run either locally or in a Continuous Integration (CI) environment. The common mental model is to interact with the project as a whole—for instance, by building the entire codebase or running the full test suite. This approach works seamlessly for small projects, but as the project scales with more modules, developers, and teams, it can turn into a productivity bottleneck.

Sooner or later, action becomes necessary—especially if you aim to maximize your CI and engineering resources, safeguard your team's [building momentum](/blog/2025/02/28/momentum), and keep pace with business demands. In this post, we’ll explore key areas where optimizations can be implemented, along with potential challenges that may emerge when accelerating your test suite. Let’s dive in.

## Run tests in parallel

Modern hardware, such as Apple Silicon-powered laptops and CI environments, boasts multiple cores, enabling true parallelism—running multiple tasks simultaneously. While parallelism is a powerful tool, it’s not always necessary, as many applications are I/O-bound, meaning they spend time waiting for input/output operations to complete rather than taxing the CPU. In testing, for example, while one test awaits the completion of an asynchronous operation, the test runner can leverage shared resources to execute other tests concurrently.

In Swift Testing, parallel execution is enabled by default. However, with XCTest, you may need to opt in via the test plan settings. If you’re using `xcodebuild`, you can control parallelization with these options:

```
-parallel-testing-enabled YES|NO                         overrides the per-target setting in the scheme
-parallel-testing-worker-count NUMBER                    the exact number of test runners that will be spawned during parallel testing
-maximum-parallel-testing-workers NUMBER                 the maximum number of test runners that will be spawned during parallel testing
```

One might assume parallelization is the ultimate solution for speeding up test execution. Yet, as soon as you enable it, new challenges surface that you may not have anticipated.

### Environment limitations

Parallelization has its limits. For instance, UI tests often rely on simulators, which are resource-intensive and can’t be spawned indefinitely. You might hit a ceiling where adding more parallel tasks yields diminishing returns due to hardware or system constraints.

### Code not designed for parallel access

Functional programming advocates for avoiding shared mutable state to ensure determinism—a principle that also facilitates parallelization by scoping state to individual functions. While Swift supports functional programming, shared mutable state often creeps in via static variables or singletons. When you increase parallelization, this global state can lead to two issues:

- **Data Races:** Multiple threads accessing the same memory simultaneously can cause crashes or undefined behavior during test execution.
- **Race Conditions:** Tests whose outcomes depend on execution order may become flaky, as detailed in resources like [JetBrains' guide on flaky tests](https://www.jetbrains.com/teamcity/ci-cd-guide/concepts/flaky-tests/).

To fully harness parallelization, you’ll likely need to refactor your code to eliminate shared state. This involves scoping state to each test and passing it explicitly to the logic under test. To avoid verbose dependency injection, consider libraries like [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) from Point-Free or Apple’s [swift-service-context](https://github.com/apple/swift-service-context). These tools allow each test to instantiate its dependencies, providing a clean API for runtime access.

For data races, enabling [Complete Concurrency Checking](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/completechecking) in Swift 6 is invaluable. While often touted for app stability, it’s equally critical for reliable parallel test execution, catching potential races at compile time.

## Parallelization across environments

When single-environment limits—like the number of available simulators—cap your parallelization, you can distribute tests across multiple CI environments. For example, if one environment supports only 4 simulators, adding a second environment doubles your capacity to 8.

To achieve this, decouple building from testing. Use the `build-for-testing` option in `xcodebuild` to compile your scheme without running tests:

```bash
xcodebuild \
    -workspace MyApp.xcworkspace \
    -scheme MyApp \
    -sdk iphonesimulator \
    -destination 'generic/platform=iOS' \
    build-for-testing
```

This generates an `.xctestrun` file in the default DerivedData directory (`~/Library/Developer/Xcode/DerivedData/`). This file bundles everything needed to run tests and must be transferred from the build environment to each test-running environment. To locate it, use:

```bash
XCTEST_RUN_PATH=$(find ~/Library/Developer/Xcode/DerivedData/ -name "*.xctestrun")
```

In a CI system like GitHub Actions, cache the file with:

```yaml
- name: Cache .xctestrun
  id: xctestrun-cache
  uses: actions/cache/save@v4
  with:
    path: ~/Library/Developer/Xcode/DerivedData/**/*.xctestrun
    key: xctestrun-${{ github.run_id }}-${{ github.run_attempt }}
```

Restore it in test environments with:

```yaml
- name: Restore .xctestrun
  uses: actions/cache/restore@v4
  with:
    key: xctestrun-${{ github.run_id }}-${{ github.run_attempt }}
```

Then execute tests with `test-without-building`, specifying the .xctestrun file:

```bash
xcodebuild \
    -workspace MyApp.xcworkspace \
    -scheme MyApp \
    -sdk iphonesimulator \
    -destination 'generic/platform=iOS' \
    -xctestrun $(find ~/Library/Developer/Xcode/DerivedData/ -name "*.xctestrun") \
    -only-testing Tests1 \
    test-without-building
```

> Dynamic test splitting isn’t supported natively. Use test identifiers (e.g., test case names or targets) to group and distribute tests manually.

To estimate total execution time, use this formula, assuming tests within each environment run fully in parallel:

Total time = ( Total tests / ( Environment parallelization limit x Environments) ) x Average time per test

For example, with 200 UI tests averaging 5 seconds each and a per-environment limit of 4 simulators:

- **1 environment:** Compilation time + 4.1 minutes
- **2 environments:** Compilation time + 2.08 minutes
- **3 environments:** Compilation time + 1.38 minutes
- **4 environments:** Compilation time + 1.04 minutes

## Run fewer tests

Running an entire test suite for every commit is not necessary. If you change a few lines of code in a pull request (PR), you should only run the tests that are directly or transitively connected to the change. The question is: how do you identify these tests?

Solutions have emerged in this ecosystem and others to solve this problem, often referred to as selective test running. One such solution is [XcodeSelectiveTesting](https://github.com/mikeger/XcodeSelectiveTesting) by [Mike Gerasymenko](https://github.com/mikeger), which uses the Git repository to determine changes in files and combines that information with the project's graph to identify the tests that need to run. By default, it compares against a baseline branch, but it can alternatively compare against a locally persisted changeset.

We also [provide a solution](https://docs.tuist.dev/en/guides/develop/selective-testing) that takes a different approach. Instead of relying on Git, we use fingerprinting to obtain a hash of the modules that have changed. We also handle persisting the information for you, ensuring that the incrementality of selective testing works across branches and commits, not just from a branch and the base reference. You can use it with [generated projects](https://docs.tuist.dev/en/guides/develop/projects) as well as standard Xcode projects.



## Speed up compilation

Before tests can run, the code must be compiled—a costly step in clean CI environments. Optimize this with build systems like [Bazel](https://bazel.build/) or [Tuist Cache](https://docs.tuist.dev/en/guides/develop/cache), which cache build artifacts to skip redundant compilation in clean builds.

## Closing words

Rapid feedback on pull requests empowers developers to iterate quickly and meet business goals. While multitasking during long CI runs is an option, it often hampers focus and productivity. The closer you get to instant feedback, the better your team can perform.

If your CI pipelines haven’t been revisited since their inception, it’s time to invest in optimization. Your team, business, and customers will reap the rewards of faster, more efficient workflows.
