---
title: tuist run
slug: '/commands/run'
description: "Learn how to use Tuist's run command to run schemes."
---

Depending on the project you're working on and the kind of build products you're working with, you may want to run them. However, running build products will differ depending on the type of product being built. For example, in a command line application you may just want to run the executable and provide it arguments, but for an iOS application you probably want to install and run the app on a simulator. To manage all these different use cases, you can leverage the power of `tuist run <scheme>`. 

`tuist run <scheme>` enables running all your build products with a simple interface. The project will be generated, built and the suitable scheme will be run.

:::warning Work in progress
This feature is currently being worked and may experience breaking changes.

Currently, only command line applications and iOS apps have been tested.
:::

### Arguments

| Argument            | Short | Description                                                         | Default           | Required |
| ------------------- | ----- | ------------------------------------------------------------------- | ----------------- | -------- |
| `--generate`        | n/a   | `When passed, it generates the project before testing it.`          | False             | No       |
| `--clean`           | n/a   | `When passed, it cleans the project before testing it.`             | False             | No       |
| `--path`            | `-p`  | `The path to the directory that contains the project to be tested.` | Current directory | No       |
| `--configuration`   | `-C`  | `The configuration to be used when building the scheme.`            |                   | No       |
| `--device`          | `-d`  | `Test on a specific device.`                                        |                   | No       |
| `--os`              | `-o`  | `Test with a specific version of the OS.`                           |                   | No       |
