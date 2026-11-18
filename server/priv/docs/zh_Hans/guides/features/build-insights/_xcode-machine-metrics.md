## 机器指标 {#machine-metrics}

构建洞察可以包含在构建期间捕获的机器级性能指标（CPU、内存、网络和磁盘使用情况）。要启用此功能，请设置一个轻量级的后台守护进程，持续采样系统指标：

```bash
tuist setup insights
```

这将运行一个本地守护进程，在后台采样指标。数据会被 `tuist inspect build` 自动采集并随构建报告一起上传。

> [!TIP]
> **CI**
>
> 在构建之前，在你的 CI 机器上运行 `tuist setup insights`，以便也在那里捕获机器指标。

要停止收集机器指标，请运行：

```bash
tuist teardown insights
```

这将卸载守护进程的 LaunchAgent，移除其 plist 文件，并从 `~/.local/state` 中删除采样的指标和守护进程日志，因此不会有任何内容在后台继续运行。
