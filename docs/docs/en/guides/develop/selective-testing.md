---
title: Selective testing
titleTemplate: :title · Develop · Guides · Tuist
description: Use selective testing to run only the tests that have changed since the last successful test run.
---

# Selective testing {#selective-testing}

As your project grows, so does the amount of your tests. For a long time, running all tests on every PR or push to `main` takes tens of seconds. But this solution does not scale to thousands of tests your team might have.

On every test run on the CI, you most likely re-run all the tests, regardless of the changes. Tuist's selective testing helps you to drastically speed up running the tests themselves by running only the tests that have changed since the last successful test run.

Selective testing works with `xcodebuild`, which supports any Xcode project, or if you generate your projects with Tuist, you can use the `tuist test` command instead that provides some extra convenience such as integration with the <LocalizedLink href="/guides/develop/build/cache">binary cache</LocalizedLink>. To get started with selective testing, follow the instructions based on your project setup:
- <LocalizedLink href="/guides/develop/selective-testing/xcodebuild">xcodebuild</LocalizedLink>
- <LocalizedLink href="/guides/develop/selective-testing/generated-project">Generated project</LocalizedLink>

> [!WARNING] MODULE VS FILE-LEVEL GRANULARITY
> Due to the impossibility of detecting the in-code dependencies between tests and sources, the maximum granularity of selective testing is at the target level. Therefore, we recommend keeping your targets small and focused to maximize the benefits of selective testing.
