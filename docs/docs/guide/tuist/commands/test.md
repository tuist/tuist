---
title: tuist test
description: "'tuist test' is a more user-friendly and feature-rich command to test projects."
---

# Test

### Supported platforms

| Platform | Available |
|----- | ----- |
| Apple (Native) | This command wraps `xcodebuild` making it more user-friendly and giving it superpowers with advanced features |

---

Tuist provides a command, `tuist test` to generate the project if needed, and then run the tests with the the platform-specific build tool (e.g. `xcodebuild` for Apple platforms).

## Why `tuist test`

You might wonder what's the value of using `tuist test` over generating the project with `tuist generate` and running the tests with the platform-specific build tool.

- **Single command:** `tuist test` ensures the project is generated if needed before compiling the project.
- **Beautified output:** Tuist enriches the output using tools like [xcbeautify](https://github.com/cpisciotta/xcbeautify) that make the output more user-friendly.
- [**Cache:**](/guide/cache) It optimizes the build by deterministically reusing the build artifacts from a remote cache.
- [**Smart runner:**](/guide/tests/smart-runner) It runs only the tests that need to be run, saving time and resources.
- [**Flakiness:**](/guide/tests/flakiness) Prevent, detect, and fix flaky tests.

## Usage

To run the tests of a project, you can use the `tuist test` command. This command will generate the project if needed, and then run the tests using the platform-specific build tool. We support the use of the `--` terminator to forward all subsequent arguments directly to the build tool.

#### Apple (Native) examples

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
