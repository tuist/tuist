---
title: tuist test
slug: '/commands/test'
description: 'Learn how to test your Tuist projects by simply using the test command that is optimized for minimal configuration.'
---

Whenever you don't want to run tests from Xcode, for whatever reason, you have to resort to `xcodebuild`.
While being a fine piece of software, it's really hard to get all its arguments **just right**
when you want to do something simple.

This is why we think we can do better - just by running `tuist test` we will run _all_ test targets in your app.
But not only that, we will automatically choose the right device for you - preferring the device you have already booted
or choosing one with the correct iOS version and boot it for you. Easy!

### Caching

Tuist also _automatically_ caches successful test runs - this means that the subsequent `tuist test` calls will
test only what has changed! You will see which test targets are skipped in the log.
This is extremely useful especially on CI - if you make a simple change in a module that other targets
do not depend on, CI can test only this module and nothing else.

### Command

As we said, we strive for the test command being really simple - but it should be powerful enough to be useful for all your
test-related wishes. Let's see it in more detail below.

**Test the project in the current directory**

```bash
tuist test
```

**Test a specific scheme**

```bash
tuist test MyScheme
```

**Test on a specific device and OS version**

```bash
tuist test --device "iPhone X" --os 14.0
```

:::note Standard commands
One of the benefits of using Tuist over other automation tools is that developers can get familiar with a set of commands that they can use in any Tuist project.
:::

### Arguments

| Argument               | Short | Description                                                         | Default           | Required |
| ---------------------- | ----- | ------------------------------------------------------------------- | ----------------- | -------- |
| `--clean`              | `-c`  | `When passed, it cleans the project before testing it.`             | False             | No       |
| `--path`               | `-p`  | `The path to the directory that contains the project to be tested.` | Current directory | No       |
| `--device`             | `-d`  | `Test on a specific device.`                                        |                   | No       |
| `--os`                 | `-o`  | `Test with a specific version of the OS.`                           |                   | No       |
| `--configuration`      | `-C`  | `The configuration to be used when building the scheme.`            |                   | No       |
| `--skip-ui-tests`      | n/a   | `When passed, it skips testing UI Tests targets.`                   | False             | No       |
| `--result-bundle-path` | `-T`  | `Path where test result bundle will be saved`                       |                   | No       |
| `--retry-count`        | n/a   | `Tests will retry <number> of times until they succeed.`              | 0                 | No       |
