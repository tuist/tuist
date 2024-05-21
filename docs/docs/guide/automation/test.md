---
title: Test
description: Learn how to use Tuist to run tests for your projects
---

# Test

Tuist projects can declare test targets that run tests for the project. Traditionally, teams execute them using Xcode's GUI, the `xcodebuild` command-line tool, or higher-level abstraction tools like [Fastlane Scan](https://docs.fastlane.tools/actions/scan/). Tuist provides a command, `tuist test` to generate the project if needed, and then run the tests with the `xcodebuild` command-line tool.

## Why Tuist over xcodebuild

You might wonder what's the value of using `tuist test` over generating the project with `tuist generate` and running the tests with raw `xcodebuild`. 

- **Single command:** `tuist test` ensures the project is generated if needed before compiling the project.
- **Beautified output:** Tuist enriches the `xcodebuild` output using [xcbeautify](https://github.com/cpisciotta/xcbeautify)
- [**Selective testing:**](/cloud/selective-testing) If you are using Tuist Cloud, Tuist can selectively run tests based on previous runs.

### Tuist Cloud Test <Badge type="warning" text="coming" />

Test flakiness is a tremendous source of frustration for developers and loss of productivity. Therefore, we are working on a set of features that will allow preventing, detecting, and fixing flaky tests. This will require the usage of `tuist test`, so if you are not using it yet, we recommend you start using it.

## Running scheme tests

To run the tests of a project, you can use the `tuist test` command. This command will generate the project if needed, and then run the tests using the `xcodebuild` command-line tool. We support the use of the `--` terminator to forward all subsequent arguments directly to `xcodebuild`. Arguments such as `-workspace` or `-project` cannot be used because tuist takes care of them.

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
