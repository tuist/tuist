---
title: tuist test
titleTemplate: :title | Develop | Tuist
description: Learn how to run tests efficiently with Tuist.
---

# Test

Tuist provides a command, [`tuist test`](/en/cli/test) to generate the project if needed, and then run the tests with the the platform-specific build tool (e.g. `xcodebuild` for Apple platforms).

You might wonder what's the value of using [`tuist test`](/en/cli/test) over generating the project with [`tuist generate`](/en/cli/generate) and running the tests with the platform-specific build tool.

- **Single command:** [`tuist test`](/en/cli/test) ensures the project is generated if needed before compiling the project.
- **Beautified output:** Tuist enriches the output using tools like [xcbeautify](https://github.com/cpisciotta/xcbeautify) that make the output more user-friendly.
- [**Cache:**](/en/guides/develop/build/cache) It optimizes the build by deterministically reusing the build artifacts from a remote cache.
- [**Smart runner:**](/en/guides/develop/test/smart-runner) It runs only the tests that need to be run, saving time and resources.
- [**Flakiness:**](/en/guides/develop/test/flakiness) Prevent, detect, and fix flaky tests.

## Usage

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

## Pull/merge request comments

> [!IMPORTANT] REQUIREMENTS
> To get automatic pull/merge request comments, integrate your [remote project](/en/server/introduction/accounts-and-projects) with a [Git platform](/en/server/introduction/integrations#git-platforms).

When running tests in your CI environments we can correlate the test results with the pull/merge request that triggered the CI build. This allows us to post a comment on the pull/merge request with the test results.

![GitHub App example](./github-app-comment.png)
