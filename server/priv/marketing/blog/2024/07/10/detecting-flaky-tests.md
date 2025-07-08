---
title: "Tuist now supports detecting flaky tests"
category: "product"
tags: ["Tests"]
excerpt: "Tuist now supports detecting flaky tests. Learn how it works and how it can help you ship more reliable software"
author: pepicrft
---

When developing software, it's standard practice to write tests to ensure that code behaves as expected. In the Apple ecosystem, developers have been using [XCTest](https://developer.apple.com/documentation/xctest) to write tests for their Swift and Objective-C codebases. Recently, [Swift Testing](https://developer.apple.com/xcode/swift-testing/) was introduced, addressing many of XCTest's shortcomings and advancing the state of the art in testing Swift code.

## Understanding Flaky Tests

If you've written tests before, you might know that tests might yield inconsistent results across runs. These are often referred to as ["flaky tests"](https://docs.gitlab.com/ee/development/testing_guide/unhealthy_tests.html#flaky-tests). In other words, flaky tests are not deterministic. They might fail due to race conditions or dependencies on the environment in which they run.

Flaky tests can be quite frustrating and time-consuming. Imagine this scenario:

1. You change one line of Swift code in your project.
2. You push the changes upstream.
3. After waiting half an hour for results (unless you're using [Tuist cache](https://docs.tuist.io/cloud/binary-caching.html) to reduce those times), you see that your CI pipeline has failed due to a failing test unrelated to your changes.
4. Developers commonly retry the build to see if the test passes the second time.
5. Meanwhile, another contribution lands, causing conflicts in your branch.
6. After an entire hour, you're still trying to see if your changes pass on CI.
7. Finally, after 1.5 hours, your changes are green and ready to be merged.

**That's 1.5 hours of your time for a single line of code change.** This is a significant problem that many companies don't address because tools to detect flaky tests are not widely available. But we're here to change that.

## Why Flakiness is Worth Solving

**Tuist's aim is to help teams build better apps faster.** If a codebase contains flaky tests:

1. The team wastes time.
2. They might ship bugs to users because tests are not reliable.

Flaky tests are detrimental to the team's productivity and the quality of the software they ship. Therefore, we felt it was a challenge we had to help solve.

The Tuist team set out to provide a solution in **three phases:**

1. Bring awareness by detecting flakiness.
2. Help teams prevent flakiness when introducing new tests.
3. Provide tools to automatically or manually disable tests.

We're thrilled to announce that **the first phase is now available in Tuist for anyone to use.**

## Detecting Flaky Tests

You might wonder how we solved this issue. A test is flaky if it produces different results when run multiple times without changes. The key question is: *how do we know if a test has changed?*

In a standard Xcode project, this information is hard to obtain outside of Xcode's build system. An approximation could be made through static analysis of imports, but this could be inaccurate for projects using dynamic features like compile-time resolved macros or compiler directives.

Fortunately, Tuist has a great foundation to build upon. Our hashing logic, used for cache and smart test runs, allows us to determine if a test has changed. **We consider a test unchanged if the hash of its containing module remains the same.** We persist these results over time.

This happens automatically if you run your tests with [`tuist test`](https://docs.tuist.io/guide/automation/test.html). We recommend adopting this over other abstractions, as it provides access to smart test runs and analytics to understand your projects and make informed decisions.
With this information, Tuist can provide a list of tests detected as flaky. In this iteration, we just provide the list of tests for which we've noticed inconsistencies. In the future, we plan to include a score indicating how flaky a test is, based on its run history.

![An image that shows the dahboard with a list of tests, some of which have been marked as flaky](/marketing/images/blog/2024/07/10/detecting-flaky-tests/flaky-test.png)

## What's next

This is just the beginning of our work in this area. We'll iterate with teams to ensure the detection feature works well with XCTest and Swift Testing. We'll also refine the user interface to present actionable information. After that, we'll focus on preventing flakiness, which will be seamlessly integrated into the tuist test workflow. Finally, we'll provide tools to disable flaky tests, such as rules for automatic disabling or a command for manual disabling.

We believe this is a crucial feature for any team that wants to ship reliable software. If you want to try it [create an account](https://docs.tuist.dev/en/server/introduction/accounts-and-projects) and run `tuist test` in your project. We welcome your feedback and look forward to hearing from you.
