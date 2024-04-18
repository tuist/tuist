---
title: Build
description: Learn how to build projects and workspaces with Tuist
---

# Build

Xcode projects are usually built through Xcode's GUI or the `xcodebuild` command-line tool. Tuist provides a command, `tuist build`, to generate the project if needed, and then build it with the `xcodebuild` command-line tool.

## Why Tuist over xcodebuild

You might wonder what's the value of using `tuist build` over generating the project with `tuist generate` and building it with raw `xcodebuild`. 

- **Single command:** `tuist build` ensures the project is generated if needed before compiling the project.
- **Beautified output:** Tuist enriches the `xcodebuild` output using [xcbeautify](https://github.com/cpisciotta/xcbeautify)
- [**Binary caching:**](/cloud/binary-caching) If you are using Tuist Cloud, Tuist can reuse the binaries from the cache, speeding up the build process.

### Tuist Cloud Analytics <Badge type="warning" text="coming" />

Understanding the build process is crucial to optimize the build times. Unfortunately, Xcode doesn't provide a lot of insights into the build process. Therefore, we are working on a set of features that will allow you to understand the build process better. This will require the usage of `tuist build`, so if you are not using it yet, we recommend you start using it.

## Building schemes

To build schemes of a project, you can use the `tuist build` command. This command will generate the project if needed, and then build it using the `xcodebuild` command-line tool.

::: code-group
```bash [Build a scheme]
tuist build MyScheme
```
```bash [Build a specific configuration]
tuist build MyScheme --configuration Debug
```
```bash [Build all schemes without binary cache]
tuist build --no-binary-cache
```
:::

> [!NOTE] XCODEBUILD ARGUMENT FORWARDING
> We don't support forwarding arbitrary arguments to `xcodebuild` yet. If you need to pass arguments to `xcodebuild`, you can use the `--verbose` flag to see the command that Tuist is running, and then run it manually with the arguments you need.

