## 機器指標 {#machine-metrics}

建置洞察可包含在建置期間擷取的機器層級效能指標（CPU、記憶體、網路與磁碟使用量）。若要啟用此功能，請設定一個輕量的背景常駐程式，持續採樣系統指標：

```bash
tuist setup insights
```

這會執行一個本地常駐程式，在背景中採樣指標。資料會由 `tuist inspect build` 自動擷取，並隨建置報告一同上傳。

磁碟指標包含讀寫活動，以及在使用相容的 CLI 與伺服器時，macOS 系統 Data 磁碟區（`/System/Volumes/Data`）的總空間與可用空間。可用空間不包含可清除空間。磁碟空間圖表會顯示建置期間的使用空間（總空間減去可用空間）與總容量，而不僅是上傳時的數值。它不會測量用於 checkout 或 DerivedData 的獨立外部磁碟區。

升級 CLI 後，請先執行 `tuist teardown insights`，再執行 `tuist setup insights`，以重新啟動現有的採樣器。採樣必須在建置期間運行；較舊的報告與失敗的測量沒有磁碟空間數值，也不會顯示為零。磁碟空間採樣遵循現有的 90 天機器指標保留政策。

> [!TIP]
> **CI**
>
> 在建置前於你的 CI 機器上執行 `tuist setup insights`，以便同時擷取該處的機器指標。

若要停止收集機器指標，請執行：

```bash
tuist teardown insights
```

這會卸載常駐程式的 LaunchAgent、移除其 plist，並從 `~/.local/state` 刪除已採樣的指標與常駐程式日誌，確保背景中沒有任何程序繼續執行。
