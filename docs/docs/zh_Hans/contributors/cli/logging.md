---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Contributors · Tuist",
  "description": "Learn how to contribute to Tuist by reviewing code"
}
---
# 日志记录{#logging}

命令行工具采用[swift-log](https://github.com/apple/swift-log)接口进行日志记录。该包抽象了日志实现细节，使命令行工具对日志后端保持无关性。日志器通过任务局部变量进行依赖注入，可在任意位置通过以下方式访问：

```bash
Logger.current
```

信息
<!-- -->
使用`调度` 或分离任务时，任务局部变量不会传播值，因此若使用此类任务，需自行获取值并传递给异步操作。
<!-- -->
:::

## 日志记录要求{#what-to-log}

日志并非命令行界面的用户界面，而是用于诊断问题的工具。因此提供的信息越详尽越好。开发新功能时，请设身处地考虑开发者遭遇异常行为时的需求，思考哪些信息对他们最有价值。务必使用正确的日志级别(https://www.swift.org/documentation/server/guides/libraries/log-levels.html)，否则开发者将无法过滤冗余信息。
