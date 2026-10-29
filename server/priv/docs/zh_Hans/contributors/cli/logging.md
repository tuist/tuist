---
{
  "title": "日志记录",
  "titleTemplate": ":title · CLI · 贡献者 · Tuist",
  "description": "Tuist CLI 中的日志记录工作原理及贡献者指南。"
}
---
# 日志记录 {#logging}

CLI 采用 [swift-log](https://github.com/apple/swift-log) 接口进行日志记录。该包抽象了日志实现的细节，使 CLI 与日志后端无关。日志记录器通过任务局部变量进行依赖注入，可在任意位置通过以下方式访问：

```bash
Logger.current
```

> [!NOTE]
> 使用 `Dispatch` 或分离任务时，任务局部变量不会传播值，因此如果使用它们，需要获取该值并将其传递给异步操作。


## 记录什么内容 {#what-to-log}

日志不是 CLI 的用户界面。它们是用于在问题出现时进行诊断的工具。因此，提供的信息越多越好。在构建新功能时，请站在遇到意外行为的开发者角度思考，考虑哪些信息对他们有帮助。确保使用正确的 [日志级别](https://www.swift.org/documentation/server/guides/libraries/log-levels.html)。否则，开发者将无法过滤掉噪声。
