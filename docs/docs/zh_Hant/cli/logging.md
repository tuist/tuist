---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to enable and configure logging in Tuist."
}
---
# 記錄{#logging}

命令列介面會內部記錄訊息，以協助您診斷問題。

## 透過日誌診斷問題{#diagnose-issues-using-logs}

若指令執行未產生預期結果，可透過檢視日誌診斷問題。命令列介面會將日誌轉發至
[OSLog](https://developer.apple.com/documentation/os/oslog) 及檔案系統。

每次執行時，系統會在以下路徑建立日誌檔案：`$XDG_STATE_HOME/tuist/logs/{uuid}.log`
其中：`$XDG_STATE_HOME` 若環境變數未設定，則取值為：`~/.local/state`
您亦可透過設定：`$TUIST_XDG_STATE_HOME` 來指定 Tuist 專屬狀態目錄，此設定將優先於：`$XDG_STATE_HOME`

::: tip
<!-- -->
欲深入瞭解 Tuist 的目錄組織架構及自訂目錄設定方式，請參閱
<LocalizedLink href="/cli/directories">目錄文件</LocalizedLink>。
<!-- -->
:::

預設情況下，當執行異常終止時，CLI 會輸出日誌路徑。若未顯示，您可於上述路徑中查閱日誌（即最新日誌檔案）。

::: warning
<!-- -->
敏感資訊未經遮蔽處理，分享日誌時請謹慎行事。
<!-- -->
:::

### 持續整合{#diagnose-issues-using-logs-ci}

在 CI 環境中，由於環境屬一次性使用性質，您可能需要設定 CI 管線以匯出 Tuist 日誌。匯出建置產物是各 CI
服務的通用功能，具體設定取決於您使用的服務。例如在 GitHub Actions 中，可使用 ``` 指令執行
`actions/upload-artifact`` 操作，將日誌作為建置產物上傳：

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

### 快取守護程序除錯{#cache-daemon-debugging}

為偵錯快取相關問題，Tuist 會透過以下設定記錄快取守護程序操作：`os_log` 子系統`dev.tuist.cache`
您可使用以下指令即時串流這些日誌：

```bash
log stream --predicate 'subsystem == "dev.tuist.cache"' --debug
```

這些記錄亦可透過在Console.app中篩選`開發者.tuist.cache`
子系統來檢視。此子系統提供關於快取操作的詳細資訊，有助於診斷快取上傳、下載及通訊問題。
