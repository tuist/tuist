---
title: tuist test
titleTemplate: :title · Develop · Guides · Tuist
description: Learn how to run tests efficiently with Tuist.
---

# Test {#test}

Tuist provides a command, <LocalizedLink href="/cli/test">`tuist test`</LocalizedLink> to generate the project if needed, and then run the tests with the the platform-specific build tool (e.g. `xcodebuild` for Apple platforms).

You might wonder what's the value of using <LocalizedLink href="/cli/test">`tuist test`</LocalizedLink> over generating the project with <LocalizedLink href="/cli/generate">`tuist generate`</LocalizedLink> and running the tests with the platform-specific build tool.

- **Single command:** <LocalizedLink href="/cli/test">`tuist test`</LocalizedLink> ensures the project is generated if needed before compiling the project.
- **보기좋은 출력:** Tuist는 출력을 더 사용자 친화적으로 만들어 주는 [xcbeautify](https://github.com/cpisciotta/xcbeautify)와 같은 툴을 사용하여 출력합니다.
- <0><1>캐시:</1></0> 원격 캐시에서 빌드 artifact를 재사용하여 빌드를 최적화 합니다.
- <LocalizedLink href="/guides/develop/test/smart-runner"><bold>Smart runner:</bold></LocalizedLink> It runs only the tests that need to be run, saving time and resources.
- <LocalizedLink href="/guides/develop/test/flakiness"><bold>Flakiness:</bold></LocalizedLink> Prevent, detect, and fix flaky tests.

## 사용법 {#usage}

To run the tests of a project, you can use the `tuist test` command. This command will generate the project if needed, and then run the tests using the platform-specific build tool. We support the use of the `--` terminator to forward all subsequent arguments directly to the build tool.

::: code-group

```bash [Running scheme tests]
tuist test MyScheme
```

```bash [Running all tests without binary cache]
tuist test --no-binary-cache
```

```bash [Running all tests without selective testing]
tuist test --no-selective-testing
```

:::

## Pull/merge request comments {#pullmerge-request-comments}

> [!IMPORTANT] REQUIREMENTS
> To get automatic pull/merge request comments, integrate your <LocalizedLink href="/server/introduction/accounts-and-projects#projects">remote project</LocalizedLink> with a <LocalizedLink href="/server/introduction/integrations#git-platforms">Git platform</LocalizedLink>.

When running tests in your CI environments we can correlate the test results with the pull/merge request that triggered the CI build. This allows us to post a comment on the pull/merge request with the test results.

![GitHub App example](/images/contributors/scheme-arguments.png)
