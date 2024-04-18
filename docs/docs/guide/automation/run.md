---
title: Graph
description: Tuist provides a command to run xcodebuild-compiled artifacts such as iOS apps
---

# Run

Unlike Xcode's GUI, Xcode's CLI, `xcodebuild`, doesn't provide a way to run the compiled artifacts of your project. Tuist provides a command to run the compiled artifacts of your project, such as iOS apps.

> [!TIP] ONLY IOS APPS SUPPORTED
> We currently only support running iOS apps. Support for other platforms is planned.

## Run an iOS app

The `tuist run` command generates the project if needed, then compiles it with `xcodebuild`, and launches the built artifact from the derived data directory in the specified simulator.

::: code-group

```bash [Run on iPhone 15 with iOS 17.4.1]
tuist run MyApp --device "iPhone 15" --os "17.4.1"
```
:::

> [!NOTE] EXISTING SIMULATORS
> If Tuist can't find a destination that matches the specified device and OS, it will use the first available simulator.