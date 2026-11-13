## 机器指标 {#machine-metrics}

构建洞察可以包含在构建过程中捕获的机器级性能指标（CPU、内存、网络和磁盘使用情况）。要启用此功能，请设置一个轻量级后台守护进程，持续采样系统指标：

```bash
tuist setup insights
```

这会运行一个本地守护进程，在后台采样指标。数据会被 `tuist inspect build` 自动采集并随构建报告一起上传。

磁盘指标包括读/写活动，并且在使用兼容的 CLI 和服务器时，还包括 macOS 系统数据卷（`/System/Volumes/Data`）上的总空间和可用空间。可用空间不包括可清除空间。磁盘空间图表显示构建期间的已用空间（总空间减去可用空间）以及总容量，而不仅仅是在上传时。它不测量用于检出或 DerivedData 的独立外部卷。

升级 CLI 后，使用 `tuist teardown insights` 然后执行 `tuist setup insights` 来重启现有的采样器。采样必须在构建期间运行；旧报告和失败的测量没有磁盘空间值，也不会显示为零。磁盘空间采样遵循现有的 90 天机器指标保留策略。

> [!TIP]
> **CI**
>
> 在构建之前在 CI 机器上运行 `tuist setup insights`，以便也在那里捕获机器指标。

要停止收集机器指标，请运行：

```bash
tuist teardown insights
```

这会卸载守护进程的 LaunchAgent，移除其 plist，并从 `~/.local/state` 删除采样的指标和守护进程日志，因此不会有任何内容在后台运行。
