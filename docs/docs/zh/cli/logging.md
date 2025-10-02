---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to enable and configure logging in Tuist."
}
---
# 记录 {#logging｝

CLI 会在内部记录信息，以帮助您诊断问题。

## 使用日志诊断问题 {#diagnose-issues-using-logs}

如果命令调用没有产生预期结果，可以通过检查日志来诊断问题。CLI 会将日志转发到
[OSLog](https://developer.apple.com/documentation/os/oslog) 和文件系统。

每次运行时，它都会在`$XDG_STATE_HOME/tuist/logs/{uuid}.log` 处创建一个日志文件，其中`$XDG_STATE_HOME`
的值为`~/.local/state` （如果未设置环境变量）。

默认情况下，CLI 会在执行意外退出时输出日志路径。如果没有，则可在上述路径（即最近的日志文件）中找到日志。

> [重要信息] 敏感信息不会被编辑，因此在共享日志时要谨慎。

### 持续集成 {#diagnose-issues-using-logs-ci}

在 CI 中，环境是一次性的，您可能希望将 CI 管道配置为导出 Tuist 日志。导出工件是 CI 服务的一项通用功能，配置取决于您使用的服务。例如，在
GitHub Actions 中，可以使用`actions/upload-artifact` 操作将日志作为工件上传：

```yaml
name: Node CI

on: [push]

env:
  XDG_STATE_HOME: /tmp

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      # ... other steps
      - run: tuist generate
      # ... do something with the project
      - name: Export Tuist logs
        uses: actions/upload-artifact@v4
        with:
          name: tuist-logs
          path: /tmp/tuist/logs/*.log
```
