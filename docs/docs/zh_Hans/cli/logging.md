---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to enable and configure logging in Tuist."
}
---
# 日志记录{#logging}

CLI会在内部记录日志信息，以协助您诊断问题。

## 通过日志诊断问题{#diagnose-issues-using-logs}

若命令调用未产生预期结果，可通过检查日志诊断问题。命令行界面将日志转发至[OSLog](https://developer.apple.com/documentation/os/oslog)及文件系统。

每次运行时，它都会在`$XDG_STATE_HOME/tuist/logs/{uuid}.log` 处创建一个日志文件，其中`$XDG_STATE_HOME`
的值为`~/.local/state` （如果未设置环境变量）。也可以使用`$TUIST_XDG_STATE_HOME` 设置 Tuist
特有的状态目录，其优先级高于`$XDG_STATE_HOME` 。

::: tip
<!-- -->
了解有关 Tuist 目录组织方式以及如何配置自定义目录的详细信息，请参阅
<LocalizedLink href="/cli/directories">目录文档</LocalizedLink>。
<!-- -->
:::

默认情况下，当执行意外退出时，CLI会输出日志路径。若未输出，您可在上述路径中找到日志（即最新日志文件）。

:: 警告
<!-- -->
敏感信息未被屏蔽，分享日志时请谨慎。
<!-- -->
:::

### 持续集成{#diagnose-issues-using-logs-ci}

在CI环境中，由于环境具有临时性，您可能需要配置CI管道以导出Tuist日志。导出构建产物是CI服务普遍支持的功能，具体配置取决于所用服务。例如在GitHub
Actions中，可使用`actions/upload-artifact` 该操作将日志作为构建产物上传：

```yaml
name: Node CI

on: [push]

env:
  TUIST_XDG_STATE_HOME: /tmp

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
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: tuist-logs
          path: /tmp/tuist/logs/*.log
```

### 缓存守护进程调试{#cache-daemon-debugging}

为排查缓存相关问题，Tuist通过以下配置记录缓存守护进程操作：`os_log` 子系统设置：`dev.tuist.cache`
可通过以下命令实时流式传输日志：

```bash
log stream --predicate 'subsystem == "dev.tuist.cache"' --debug
```

这些日志也可通过在Console.app中筛选`dev.tuist.cache`
子系统查看。该子系统提供缓存操作的详细信息，有助于诊断缓存上传、下载及通信问题。
