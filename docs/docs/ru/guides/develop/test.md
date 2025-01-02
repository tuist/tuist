---
title: tuist test
titleTemplate: :title · Develop · Guides · Tuist
description: Learn how to run tests efficiently with Tuist.
---

# Test {#test}

Tuist provides a command, <LocalizedLink href="/cli/test">`tuist test`</LocalizedLink> to generate the project if needed, and then run the tests with the the platform-specific build tool (e.g. `xcodebuild` for Apple platforms).

You might wonder what's the value of using <LocalizedLink href="/cli/test">`tuist test`</LocalizedLink> over generating the project with <LocalizedLink href="/cli/generate">`tuist generate`</LocalizedLink> and running the tests with the platform-specific build tool.

- **Single command:** <LocalizedLink href="/cli/test">`tuist test`</LocalizedLink> ensures the project is generated if needed before compiling the project.
- **Beautified output:** Tuist enriches the output using tools like [xcbeautify](https://github.com/cpisciotta/xcbeautify) that make the output more user-friendly.
- <LocalizedLink href="/guides/develop/build/cache"><bold>Cache:</bold></LocalizedLink> It optimizes the build by deterministically reusing the build artifacts from a remote cache.
- <LocalizedLink href="/guides/develop/test/selective-testing"><bold>Smart runner:</bold></LocalizedLink> It runs only the tests that need to be run, saving time and resources.
- <LocalizedLink href="/guides/develop/test/flakiness"><bold>Flakiness:</bold></LocalizedLink> Prevent, detect, and fix flaky tests.

## Usage {#usage}

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
> To get automatic pull/merge request comments, integrate your <LocalizedLink href="/server/introduction/accounts-and-projects">remote project</LocalizedLink> with a <LocalizedLink href="/server/introduction/integrations#git-platforms">Git platform</LocalizedLink>.

When running tests in your CI environments we can correlate the test results with the pull/merge request that triggered the CI build. This allows us to post a comment on the pull/merge request with the test results.

![GitHub App example](/images/contributors/scheme-arguments.png)
