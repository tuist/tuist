---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to enable and configure logging in Tuist."
}
---
# 記錄{#logging}

CLI 會在內部記錄訊息，以協助您診斷問題。

## 使用日誌診斷問題{#diagnose-issues-using-logs}

如果命令調用沒有產生預期的結果，您可以透過檢查日誌來診斷問題。CLI 會將日誌轉發至
[OSLog](https://developer.apple.com/documentation/os/oslog) 和檔案系統。

每次執行時，它都會在`$XDG_STATE_HOME/tuist/logs/{uuid}.log` 建立一個記錄檔，其中`$XDG_STATE_HOME`
的值為`~/.local/state` ，如果沒有設定環境變數的話。您也可以使用`$TUIST_XDG_STATE_HOME` 來設定 Tuist
特有的狀態目錄，它優先於`$XDG_STATE_HOME` 。

::: tip
<!-- -->
瞭解更多關於 Tuist 目錄組織的資訊，以及如何在 <LocalizedLink href="/cli/directories">Directories 文件</LocalizedLink>中設定自訂目錄。
<!-- -->
:::

預設情況下，當執行意外退出時，CLI 會輸出記錄路徑。如果沒有，您可以在上述路徑中找到記錄 (即最近的記錄檔)。

::: warning
<!-- -->
敏感資訊不會被刪除，因此分享日誌時要謹慎。
<!-- -->
:::

### 持續整合{#diagnose-issues-using-logs-ci}

在 CI 中，環境是一次性的，您可能想要設定 CI 管道來匯出 Tuist 日誌。匯出工件是 CI 服務的共通能力，配置取決於您使用的服務。例如，在
GitHub Actions 中，您可以使用`actions/upload-artifact` 動作，將日誌上傳為工件：

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

### 快取 daemon 除錯{#cache-daemon-debugging}

為了除錯快取相關的問題，Tuist 使用`os_log` 與子系統`dev.tuist.cache` 記錄快取 daemon
的作業。您可以使用以下方式即時串流這些記錄：

```bash
log stream --predicate 'subsystem == "dev.tuist.cache"' --debug
```

透過過濾`dev.tuist.cache` 子系統，在 Console.app
中也可以看到這些記錄。這可提供快取操作的詳細資訊，有助於診斷快取上傳、下載和通訊問題。
