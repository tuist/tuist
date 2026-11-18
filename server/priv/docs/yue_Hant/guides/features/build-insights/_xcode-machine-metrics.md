## 機器指標 {#machine-metrics}

構建洞察可以包含在構建期間捕獲的機器級別性能指標（CPU、記憶體、網絡和磁碟使用量）。要啟用此功能，請設置一個輕量級的後台守護進程，持續採樣系統指標：

```bash
tuist setup insights
```

這會運行一個本地守護進程，在後台採樣指標。數據會由 `tuist inspect build` 自動收集並隨構建報告一起上傳。

磁碟指標包括讀/寫活動，並且在兼容的 CLI 和伺服器下，還包括 macOS 系統 Data 卷（`/System/Volumes/Data`）的總空間和可用空間。可用空間不包括可清除空間。磁碟空間圖表顯示已用空間（總空間減去可用空間）以及構建期間的總容量，而不僅僅是上傳時的狀態。它不測量用於檢出或 DerivedData 的單獨外部卷。

升級 CLI 後，請使用 `tuist teardown insights` 然後執行 `tuist setup insights` 來重啟現有的採樣器。採樣必須在構建期間運行；舊報告和失敗的測量沒有磁碟空間值，也不會顯示為零。磁碟空間採樣遵循現有的 90 天機器指標保留策略。

> [!TIP]
> **CI**
>
> 在構建之前，在你的 CI 機器上運行 `tuist setup insights`，以便也在那裡捕獲機器指標。

要停止收集機器指標，請運行：

```bash
tuist teardown insights
```

這會卸載守護進程的 LaunchAgent，移除其 plist 文件，並從 `~/.local/state` 刪除採樣的指標和守護進程日誌，因此不會有任何內容在後台運行。
