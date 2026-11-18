---
{
  "title": "數據保留",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "了解 Tuist 保留可下載構件和儀表板活動數據的時長。"
}
---
# 數據保留{#data-retention}

Tuist 對上傳的構件檔案，以及用於儀表板和洞察的記錄，分別應用不同的保留政策。刪除已過期的構件檔案不會刪除其相關的洞察記錄。

對於構件檔案，託管式 Tuist 伺服器採用以方案為基礎的保留期，上限為 30 天。在自託管實例中，構件清理預設為停用；營運人員可以選擇啟用，並為每種支援的構件類型設定獨立的保留期。

## 構件檔案{#artifact-files}

### 託管式 Tuist 伺服器{#hosted-artifact-files}

這些保留期定義了構件檔案在託管式 Tuist 伺服器上可供存取的時間長度。

| 構件 | Air 與開源版 | Pro | Enterprise |
| --- | --- | --- | --- |
| 快取構件，包括 Xcode 快取、模組快取、Gradle 快取、Bazel 遠端快取檔案，以及來自 Tuist Runners 的 GitLab CI 快取封存 | 14 天 | 30 天 | 30 天 |
| App 預覽建構與圖示 | 30 天 | 30 天 | 30 天 |
| 建構封存 | 7 天 | 30 天 | 30 天 |
| 執行構件，包括結果套件與工作階段封存 | 7 天 | 30 天 | 30 天 |
| 測試執行附件 | 30 天 | 30 天 | 30 天 |
| 分片套件 | 7 天 | 14 天 | 30 天 |

有效的帳戶方案決定託管保留期。如果帳戶沒有有效訂閱，Tuist 會使用 Air 保留期。部分構件類型採用較短的保留期，因為預期它們會被重新產生。

在 Tuist 記錄測試執行識別碼之前建立的測試附件，不會被自動刪除。在保留清理期間，Tuist 會避免進行無限制的歷史擁有權查找，因此這些檔案仍然可供存取。

### 自託管實例{#self-hosted-artifact-files}

自託管構件清理為選擇性啟用，可針對每種構件類型分別設定，且不受 30 天上限限制。請參閱<.localized_link href="/guides/server/self-host/server#artifact-retention">自託管構件保留設定</.localized_link>，了解支援的構件類型與部署選項。

## 儀表板與活動數據{#dashboard-and-activity-data}

儀表板與活動記錄的保留政策獨立於構件檔案清理。以下保留期不會因託管方案而異，包括 Enterprise。

### Xcode 建構與測試洞察{#xcode-build-and-test-insights}

核心 Xcode 建構與測試記錄目前沒有固定的時間基準刪除排程。其他報告數據，例如時間軸步驟和機器指標，會分別過期：

| 數據 | 保留期 |
| --- | --- |
| 建構摘要、每個檔案和每個目標的建構記錄，以及建構問題 | 沒有固定的時間基準刪除排程 |
| 測試執行、模組和套件結果，以及個別測試結果 | 沒有固定的時間基準刪除排程 |
| 建構時間軸步驟及其擷取的日誌 | 90 天 |
| 建構機器指標 | 90 天 |
| Xcode 專案圖記錄 | 30 天 |

這些記錄與[構件檔案保留期](#hosted-artifact-files)所涵蓋的可下載建構封存、結果套件和測試附件是分開的。在 Enterprise 方案中，這些檔案會保留 30 天；相關的建構和測試記錄在檔案過期後仍然可供存取。記錄沒有固定的時間基準刪除排程，並不保證永久可用。

### 其他儀表板與活動數據{#other-dashboard-and-activity-data}

| 數據 | 保留期 |
| --- | --- |
| Gradle 建構記錄、任務記錄、快取事件記錄、Mix 建構記錄、編譯檔案記錄、建構步驟記錄與診斷、Cargo 建構記錄（包括彙總編譯快取測量）與編譯器觀察、Bazel 呼叫、Bazel 追蹤設定檔、已索引的設定檔步驟與動作診斷、待處理的 Bazel 設定檔與測試匯入記錄、Bazel 呼叫日誌，以及 Bazel 遠端動作快取觀察 | 90 天 |
| 持久模組詳情頁面上的 Xcode 模組編譯與快取歷史 | 30 天 |
| 持久詳情頁面上的任務、聲明的 Once 動作、Bazel BEP 動作、編譯檔案和模組觀察 | 90 天，上述 Xcode 模組除外 |
| 持久任務/動作/模組/檔案身分元數據 | 365 天內無觀察 |
| Runner 工作日誌、歸檔的 Runner 日誌，以及 Runner 工作機器指標 | 90 天 |
| Webhook 傳遞歷史 | 沒有固定的刪除排程 |

持久詳情 URL 不依賴於特定建構仍然可用。它們的身分元數據可能比個別觀察更長久，因此詳情頁面在所選期間內可能沒有歷史記錄。新歷史是從功能部署後收到的報告中索引的；現有的執行層級歷史不會追溯複製。

ClickHouse 的內部`system.*`營運日誌表是在 ClickHouse 層級設定，而非由 Tuist 的產品數據保留政策設定。它們預設為無上限；捆綁的自託管 Docker Compose 和嵌入式 Helm ClickHouse 設定可以對其進行上限限制，如<.localized_link href="/guides/server/self-host/server#capping-operational-log-retention">限制營運日誌保留</.localized_link>所述。
