---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Contributors · Tuist",
  "description": "Learn how to contribute to Tuist by reviewing code"
}
---
# Logging {#logging}

The CLI embraces the [swift-log](https://github.com/apple/swift-log) interface for logging. The package abstracts away the implementation details of logging, allowing the CLI to be agnostic to the logging backend. The logger is dependency-injected using task locals and can be accessed anywhere using:

```bash
Logger.current
```

::: info
<!-- -->
Task locals don't propagate the value when using `Dispatch` or detached tasks, so if you use them, you'll need to get it and pass it to the asynchronous operation.
<!-- -->
:::

## What to log {#what-to-log}

Logs are not the CLI's UI. They are a tool to diagnose issues when they arise.
Therefore, the more information you provide, the better.
When building new features, put yourself in the shoes of a developer coming across unexpected behavior, and think about what information would be helpful to them.
Ensure you you use the right [log level](https://www.swift.org/documentation/server/guides/libraries/log-levels.html). Otherwise developers won't be able to filter out the noise.
