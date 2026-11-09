---
{
  "title": "資料保留",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "了解 Tuist 保留可下載產物與儀表板活動資料的時長。"
}
---
# 資料保留 {#data-retention}

Tuist 對上傳的構件檔案與用於儀表板和洞察的記錄套用不同的保留政策。刪除過期的構件檔案不會刪除其關聯的洞察記錄。

對於構件檔案，託管式 Tuist 伺服器使用以方案為基礎且上限為 30 天的保留區間。在自架實例中，構件清理預設為停用；管理員可以選擇啟用，並為每種支援的構件類型設定獨立的保留區間。

## 構件檔案 {#artifact-files}

### 託管式 Tuist 伺服器 {#hosted-artifact-files}

這些區間定義構件檔案在託管式 Tuist 伺服器上的可用期限。

| 構件 | Air 與開源版 | Pro | Enterprise |
| --- | --- | --- | --- |
| 快取構件，包括 Xcode 快取、模組快取、Gradle 快取、Bazel 遠端快取檔案，以及來自 Tuist Runners 的 GitLab CI 快取封存 | 14 天 | 30 天 | 30 天 |
| App 預覽建置與圖示 | 30 天 | 30 天 | 30 天 |
| 建置封存 | 7 天 | 30 天 | 30 天 |
| 執行構件，包括結果套件與工作階段封存 | 7 天 | 30 天 | 30 天 |
| 測試執行附件 | 30 天 | 30 天 | 30 天 |
| 分片套件 | 7 天 | 14 天 | 30 天 |

有效的帳戶方案決定託管保留區間。若帳戶沒有有效訂閱，Tuist 會使用 Air 保留區間。部分構件類型使用較短的區間，因為預期它們會被重新產生。

在 Tuist 記錄測試執行識別碼之前建立的測試附件，不會被自動刪除。在保留清理期間，Tuist 會避免無邊界的歷史擁有權查詢，因此這些檔案仍保持可用。

### 自架實例 {#self-hosted-artifact-files}

自架構件清理為選擇性啟用，可依每種構件類型分別設定，且不受 30 天上限限制。請參閱<.localized_link href="/guides/server/self-host/server#artifact-retention">自架構件保留設定</.localized_link>，了解支援的構件類型與部署選項。

## 儀表板與活動資料 {#dashboard-and-activity-data}

儀表板與活動記錄的保留政策獨立於構件檔案清理。下方的區間不因託管方案而異，包含 Enterprise。

### Xcode 建置與測試洞察 {#xcode-build-and-test-insights}

核心 Xcode 建置與測試記錄目前沒有固定的時間基礎刪除排程。其他報告資料（例如時間軸步驟與機器指標）則有獨立的到期規則：

| 資料 | 保留期限 |
| --- | --- |
| 建置摘要、每檔案與每目標建置記錄，以及建置問題 | 無固定時間基礎刪除排程 |
| 測試執行、模組與套件結果，以及個別測試結果 | 無固定時間基礎刪除排程 |
| 建置時間軸步驟及其擷取的日誌 | 90 天 |
| 建置機器指標 | 90 天 |
| Xcode 專案圖譜記錄 | 30 天 |

這些記錄與[構件檔案保留區間](#hosted-artifact-files)涵蓋的可下載建置封存、結果套件與測試附件是分開的。在 Enterprise 方案中，這些檔案會保留 30 天；相關建置與測試記錄在檔案過期後仍保持可用。記錄沒有固定時間基礎刪除排程，並不保證永久可用。

### 其他儀表板與活動資料 {#other-dashboard-and-activity-data}

| 資料 | 保留期限 |
| --- | --- |
| Gradle 建置記錄、工作記錄、快取事件記錄、Mix 建置記錄、編譯檔案記錄、建置步驟記錄與診斷、Cargo 建置記錄（包含彙總編譯快取測量值）與編譯器觀察、Bazel 叫用、Bazel 追蹤設定檔、已索引的設定檔步驟與動作診斷、待處理的 Bazel 設定檔與測試匯入記錄、Bazel 叫用日誌，以及 Bazel 遠端動作快取觀察 | 90 天 |
| 持久模組詳細頁面上的 Xcode 模組編譯與快取歷史 | 30 天 |
| 持久詳細頁面上的工作、宣告的 Once 動作、Bazel BEP 動作、編譯檔案與模組觀察 | 90 天，上述 Xcode 模組除外 |
| 持久工作/動作/模組/檔案身分中繼資料 | 365 天內無觀察 |
| Runner 工作日誌、歸檔的 Runner 日誌，以及 Runner 工作機器指標 | 90 天 |
| Webhook 傳遞歷史 | 無固定刪除排程 |

持久詳細 URL 不依賴特定建置保持可用。它們的身分中繼資料可能比個別觀察存續更久，因此詳細頁面在所選期間內可能沒有歷史記錄。新歷史記錄會從功能部署後收到的報告中建置索引；現有的執行層級歷史記錄不會回溯複製。

ClickHouse 的內部 `system.*` 營運日誌表格是在 ClickHouse 層級設定，而非由 Tuist 的產品資料保留政策管理。它們預設為無上限；隨附的自架 Docker Compose 與內嵌 Helm ClickHouse 設定可以限制它們，如<.localized_link href="/guides/server/self-host/server#capping-operational-log-retention">限制營運日誌保留</.localized_link>所述。
