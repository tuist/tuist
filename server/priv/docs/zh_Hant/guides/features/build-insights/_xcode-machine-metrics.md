## 機器指標 {#machine-metrics}

建置洞察可包含在建置期間擷取的機器層級效能指標（CPU、記憶體、網路與磁碟使用量）。若要啟用此功能，請設定一個輕量級的常駐程式，持續採樣系統指標：

```bash
tuist setup insights
```

這會執行一個本地常駐程式，在背景中採樣指標。資料會由 `tuist inspect build` 自動擷取，並隨建置報告上傳。

> [!TIP]
> **CI**
>
> 在建置前於你的 CI 機器上執行 `tuist setup insights`，以同時擷取該處的機器指標。

若要停止收集機器指標，請執行：

```bash
tuist teardown insights
```

這會卸載常駐程式的 LaunchAgent、移除其 plist，並從 `~/.local/state` 刪除已採樣的指標與常駐程式日誌，確保沒有任何程序在背景繼續執行。
