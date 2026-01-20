---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Contributors · Tuist",
  "description": "Learn how to contribute to Tuist by reviewing code"
}
---
# 记录{#logging}

CLI 采用 [swift-log](https://github.com/apple/swift-log) 接口记录日志。该软件包抽象了日志记录的实现细节，使
CLI 与日志记录后端无关。日志记录器通过任务本地注入依赖关系，可在任何地方使用

```bash
Logger.current
```

信息
<!-- -->
在使用`Dispatch` 或分离任务时，任务本地不会传播该值，因此如果使用它们，则需要获取该值并将其传递给异步操作。
<!-- -->
:::

## 记录什么{#what-to-log}

日志不是 CLI
的用户界面。日志是在出现问题时诊断问题的工具。因此，提供的信息越多越好。在构建新功能时，设身处地地为遇到意外行为的开发人员着想，想想哪些信息会对他们有帮助。确保使用正确的
[日志级别](https://www.swift.org/documentation/server/guides/libraries/log-levels.html)。否则，开发人员将无法过滤掉噪音。
