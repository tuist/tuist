---
title: 選択的テスト
titleTemplate: :title · Develop · Guides · Tuist
description: Use selective testing to run only the tests that have changed since the last successful test run.
---

# Selective testing {#selective-testing}

As your project grows, so does the amount of your tests. For a long time, running all tests on every PR or push to `main` takes tens of seconds. But this solution does not scale to thousands of tests your team might have.

On every test run on the CI, you most likely re-run all the tests, regardless of the changes. Tuist's selective testing helps you to drastically speed up running the tests themselves by running only the tests that have changed since the last successful test run based on our <LocalizedLink href="/guides/develop/projects/hashing">hashing algorithm</LocalizedLink>.

Selective testing works with `xcodebuild`, which supports any Xcode project, or if you generate your projects with Tuist, you can use the `tuist test` command instead that provides some extra convenience such as integration with the <LocalizedLink href="/guides/develop/build/cache">binary cache</LocalizedLink>. To get started with selective testing, follow the instructions based on your project setup:

- <LocalizedLink href="/guides/develop/selective-testing/xcodebuild">xcodebuild</LocalizedLink>
- <LocalizedLink href="/guides/develop/selective-testing/generated-project">Generated project</LocalizedLink>

> [!WARNING] MODULE VS FILE-LEVEL GRANULARITY
> Due to the impossibility of detecting the in-code dependencies between tests and sources, the maximum granularity of selective testing is at the target level. Therefore, we recommend keeping your targets small and focused to maximize the benefits of selective testing.

## Pull/merge request comments {#pullmerge-request-comments}

> [!IMPORTANT] INTEGRATION WITH GIT PLATFORM REQUIRED
> To get automatic pull/merge request comments, integrate your <LocalizedLink href="/server/introduction/accounts-and-projects">Tuist project</LocalizedLink> with a <LocalizedLink href="/server/introduction/integrations#git-platforms">Git platform</LocalizedLink>.

Once your Tuist project is connected with your Git platform such as [GitHub](https://github.com), and you start using `tuist xcodebuild test` or `tuist test` as part of your CI wortkflow, Tuist will post a comment directly in your pull/merge requests, including which tests were run and which skipped:
![GitHub app comment with a Tuist Preview link](/images/guides/develop/github-app-comment.png)
