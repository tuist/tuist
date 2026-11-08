## 機器指標 {#machine-metrics}

建構洞察可以包含在建構期間擷取的機器層級效能指標（CPU、記憶體、網絡和磁碟使用量）。要啟用此功能，請設定一個輕量級的後台守護程序，持續採樣系統指標：

```bash
tuist setup insights
```

這會運行一個本地守護程序，在後台採樣指標。數據會由 `tuist inspect build` 自動收集並隨建構報告上傳。

> [!TIP]
> **CI**
>
> 在建構之前，於你的 CI 機器上運行 `tuist setup insights`，以同時擷取那裡的機器指標。

要停止收集機器指標，請運行：

```bash
tuist teardown insights
```

這會卸載守護程序的 LaunchAgent，移除其 plist，並從 `~/.local/state` 刪除已採樣的指標和守護程序日誌，確保沒有東西在後台繼續運行。
