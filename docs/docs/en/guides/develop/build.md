---
title: Build
titleTemplate: ":title | Develop | Tuist"
description: Learn how to use Tuist to build your projects efficiently.
---

# Build

Projects are usually built through a build-system-provided CLI (e.g. `xcodebuild`). Tuist wraps them to improve the user experience and integrate the workflows with the platform to provide optimizations and analytics.

You might wonder what's the value of using `tuist build` over generating the project with `tuist generate` (if needed) and building it with the platform-specific CLI. Here are some reasons:

- **Single command:** `tuist build` ensures the project is generated if needed before compiling the project.
- **Beautified output:** Tuist enriches the output using tools like [xcbeautify](https://github.com/cpisciotta/xcbeautify) that make the output more user-friendly.
- [**Cache:**](/guides/develop/build/cache) It optimizes the build by deterministically reusing the build artifacts from a remote cache.
- **Analytics:** It collects and reports metrics that are correlated with other data points to provide you with actionable information to make informed decisions.

## Usage

`tuist build` generates the project if needed, and then build it using the platform-specific build tool. We support the use of the `--` terminator to forward all subsequent arguments directly to the underlying build tool. This is useful when you need to pass arguments that are not supported by `tuist build` but are supported by the underlying build tool.

::: code-group
```bash [Build a scheme]
tuist build MyScheme
```
```bash [Build a specific configuration]
tuist build MyScheme -- -configuration Debug
```
```bash [Build all schemes without binary cache]
tuist build --no-binary-cache
```
:::
