---
{
  "title": "除錯",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "學習如何透過日誌和網絡記錄來排查 Tuist 的問題。"
}
---
# 偵錯 {#debugging}

當指令行為不如預期時，Tuist 提供多種工具協助你診斷問題。

> [!WARNING]
> 工作階段資料可能包含敏感資訊，例如檔案路徑、專案名稱以及請求／回應內文。雖然敏感標頭（例如 Authorization）會被遮蔽，但與他人分享工作階段資料時仍須謹慎。


## 工作階段資料 {#session-data}

如果執行指令未得到預期結果，你可以檢查工作階段資料來診斷問題。CLI 會將日誌轉送至 [OSLog](https://developer.apple.com/documentation/os/oslog) 及檔案系統。

每次執行時，它會在 `$XDG_STATE_HOME/tuist/sessions/{uuid}/` 建立一個工作階段目錄；若未設定環境變數，`$XDG_STATE_HOME` 的值為 `~/.local/state`。你也可以使用 `$TUIST_XDG_STATE_HOME` 設定 Tuist 專屬的狀態目錄，其優先順序高於 `$XDG_STATE_HOME`。

每個工作階段目錄包含：
- **`logs.txt`** - CLI 工作階段的文字日誌
- **`network.har`** - [HTTP Archive (HAR)](https://w3c.github.io/web-performance/specs/HAR/Overview.html) 檔案，包含工作階段期間發出的所有網路請求與回應

### 檢視 HAR 檔案 {#visualizing-har-files}

HAR 檔案會記錄工作階段期間的所有 HTTP 請求與回應，有助於偵錯伺服器通訊問題。你可以使用以下工具開啟 HAR 檔案：

- **[Proxyman](https://proxyman.io/)**：原生 macOS 應用程式，用於檢視與分析 HTTP 流量。透過「File > Import」匯入 HAR 檔案。
- **瀏覽器開發者工具**：Chrome、Firefox 與 Safari 均支援在其「Network」分頁中匯入 HAR 檔案。
- **[HAR Viewer](http://www.softwareishard.com/har/viewer/)**：網頁版 HAR 檔案檢視器。

> [!TIP]
> 在<.localized_link href="/cli/directories">目錄文件</.localized_link>中了解更多關於 Tuist 的目錄組織方式，以及如何設定自訂目錄。


預設情況下，當執行意外結束時，CLI 會輸出工作階段路徑。若沒有輸出，你可以在上述路徑中找到工作階段資料（即最近的工作階段目錄）。

超過 5 天的工作階段目錄會自動清理。Tuist 預設最多保留 50 個非作用中工作階段目錄，同時保留目前執行中的 Tuist 程序所擁有的工作階段。在使用相同狀態目錄執行大量 Tuist 指令的 CI 環境中，你可以透過 `TUIST_SESSION_MAX_SESSIONS` 提高非作用中工作階段的上限，例如 `TUIST_SESSION_MAX_SESSIONS=200`。無效值、零或負值會被忽略，Tuist 會回退至預設值 50。

### 持續整合 {#diagnose-issues-using-logs-ci}

在 CI 環境中，由於環境是暫時性的，你可能希望設定 CI 流程以匯出 Tuist 工作階段資料。匯出構件是各 CI 服務的常見功能，具體設定取決於你使用的服務。例如，在 GitHub Actions 中，你可以使用 `actions/upload-artifact` action 將工作階段資料作為構件上傳：

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
      - name: Export Tuist session data
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: tuist-sessions
          path: /tmp/tuist/sessions/
```

### Xcode 快取偵錯 {#cache-daemon-debugging}

若要偵錯 Xcode 快取問題，請在執行 `tuist setup cache` 及建構時，將 `TUIST_CAS_LOG` 設定為檔案路徑。Tuist 會將快取統計資料與錯誤附加至該檔案：

```bash
export TUIST_CAS_LOG=$HOME/.local/state/tuist/cas.log
tuist setup cache
xcodebuild build -scheme YourScheme
```

在 CI 上，Tuist 會在無需任何設定的情況下，將此日誌寫入 `~/.local/state/tuist/cas.log`。

## 調整網路逾時與重試 {#tuning-network-timeouts}

Tuist 的所有 [超文本傳輸協定 (HTTP)](https://developer.mozilla.org/en-US/docs/Web/HTTP) 流量（包括伺服器呼叫、Registry、Previews 以及快取構件傳輸）都會透過共用 `URLSession` 進行，並採用合理的預設值。在緩慢或擁塞的網路路徑上（例如，透過企業代理伺服器存取物件儲存的自託管設定），單一請求可能會因資源不足而在完成前觸及資源逾時。特別是對於快取下載，觸及逾時會使 Tuist 回退到從原始碼建構模組，這比多等一段時間以取得快取二進位檔的成本高得多。你可以透過環境變數調整底層設定；若未設定或設為無效值，則套用預設值：

```bash
# Maximum time (in seconds) a single resource transfer can take before it's cancelled
# (default: 90, or 600 for whole-file transfers such as test-product shard artifacts)
export TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE=600

# Maximum time (in seconds) to wait for new data on an existing request (default: 120)
export TUIST_HTTP_TIMEOUT_INTERVAL_FOR_REQUEST=300

# Maximum number of simultaneous connections per host (default: 20)
export TUIST_HTTP_MAXIMUM_CONNECTIONS_PER_HOST=40

# Maximum retries after the initial attempt (default: 3, maximum: 10)
export TUIST_HTTP_MAXIMUM_RETRY_COUNT=1

# Initial exponential backoff delay in milliseconds (default: 100, maximum: 30000)
export TUIST_HTTP_RETRY_BASE_DELAY_IN_MILLISECONDS=250
```

資源逾時是整個傳輸過程的牆鐘時間上限，而非停滯保護機制，因此必須足夠大以容納你傳輸的最大構件。整檔傳輸（例如分片下載的測試產品）因此預設為 10 分鐘而非 90 秒；若傳輸停滯且沒有新資料，仍會在 `TUIST_HTTP_TIMEOUT_INTERVAL_FOR_REQUEST` 後失敗。這些傳輸只會讀取 `TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE` 以提高上限，絕不會將其降低至 10 分鐘以下，因此選擇讓快取請求快速失敗的值，不會同時取消分片下載其測試產品。提高 `TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE` 可讓可恢復但緩慢的下載完成，而非逾時。對於快取下載而言，這意味著達成快取命中，而非回退到從原始碼建構，因此請刻意提高該值：讓緩慢快取下載持續進行的同一個值，也會延遲回退到從原始碼建構。降低 `TUIST_HTTP_MAXIMUM_RETRY_COUNT` 可避免較長的逾時在多次嘗試中將最壞情況的等待時間倍增。重試延遲會在每次失敗後加倍，包含最多一個基礎延遲的隨機抖動，且永不超過 30 秒。

## 信任自訂 CA 憑證 {#trusting-a-custom-ca-certificate}

預設情況下，Tuist 會根據作業系統的根憑證儲存區驗證 TLS 憑證。當你執行使用私有憑證授權單位的自託管 Tuist 或 Kura 伺服器時，Tuist 也需要信任該 CA。將根憑證安裝至系統金鑰圈（並標示為受信任以用於 SSL）是標準做法，但在無頭 CI 主機上往往不切實際，因為沒有 GUI 工作階段或行動裝置管理 (MDM) 來設定信任旗標。

在這些情況下，你可以直接讓 Tuist 指向 CA 憑證捆綁包。該捆綁包可以是 PEM（一個或多個串連的 `-----BEGIN CERTIFICATE-----` 區塊）或單一 DER 檔案。系統根憑證儲存區會與其並存保持受信任，因此公開憑證仍會正常驗證，且不會繞過憑證評估。

```bash
# Path to a PEM/DER CA bundle to trust on top of the system root store (default: unset)
export TUIST_CA_CERTIFICATE=/etc/ssl/certs/self-hosted-ca.pem
```

你也可以在<.localized_link href="/references/tuist-toml">設定檔</.localized_link>中宣告：

```toml
[network]
ca_certificate = "/etc/ssl/certs/self-hosted-ca.pem"
```

`TUIST_CA_CERTIFICATE` 環境變數的優先順序高於設定檔，這使得將其作為 CI 機密提供變得方便，而無需更改已提交的清單。
