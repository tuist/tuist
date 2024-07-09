---
title: tuist run
description: "'tuist run' is a command to build and run the compiled artifacts of your project."
---

# Run

### Supported platforms

| Platform | Available |
|----- | ----- |
| Apple (Native) | This command wraps `xcodebuild` and `simctl` to run the compiled artifacts of your project. **Note** that only iOS apps are supported. |

---

`tuist run` is an interactive command to build and run the compile artifacts of your project.

## Usage

The `tuist run` command generates the project if needed, then compiles it with with the platform-specific build tool, and launches the built artifact from the selected destination.

#### Apple (Native) examples

::: code-group

```bash [Run on iPhone 15 with iOS 17.4.1]
tuist run MyApp --device "iPhone 15" --os "17.4.1"
```
:::

> [!NOTE] EXISTING SIMULATORS
> If Tuist can't find a destination that matches the specified device and OS or none is provided, it will ask in which available simulator to run, in case of many available, or pick the only one available otherwise.
