---
title: Логирование
titleTemplate: :title · CLI · Contributors · Tuist
description: Узнайте, как внести вклад в Tuist, проводя ревью на пулл-реквесты
---

# Логирование {#logging}

The CLI embraces the [swift-log](https://github.com/apple/swift-log) interface for logging. The package abstracts away the implementation details of logging, allowing the CLI to be agnostic to the logging backend. The logger is dependency-injected using [swift-service-context](https://github.com/apple/swift-service-context) and can be accessed anywhere using:

```bash
ServiceContext.current?.logger
```

> [!NOTE]
> `swift-service-context` passes the instance using [task locals](https://developer.apple.com/documentation/swift/tasklocal) which don't propagate the value when using `Dispatch`, so if you run asynchronous code using `Dispatch`, you'll to get the instance from the context and pass it to the asynchronous operation.

## What to log {#what-to-log}

Logs are not the CLI's UI. They are a tool to diagnose issues when they arise.
Therefore, the more information you provide, the better.
When building new features, put yourself in the shoes of a developer coming across unexpected behavior, and think about what information would be helpful to them.
Ensure you you use the right [log level](https://www.swift.org/documentation/server/guides/libraries/log-levels.html). Otherwise developers won't be able to filter out the noise.
