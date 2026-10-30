---
{
  "title": "資料保留",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "了解 Tuist 保留可下載構件與儀表板活動資料的時長。"
}
---
# 資料保留 {#data-retention}

Tuist 對上傳的構件檔案與用於儀表板和洞察的記錄套用不同的保留政策。刪除已過期的構件檔案不會刪除其關聯的洞察記錄。

對於構件檔案，託管式 Tuist 伺服器採用以方案為基礎的保留期間，上限為 30 天。在自託管實例中，構件清理預設為停用；營運者可選擇啟用，並為每種支援的構件類型設定獨立的保留期間。

## 構件檔案 {#artifact-files}

### 託管式 Tuist 伺服器 {#hosted-artifact-files}

這些期間定義了構件檔案在託管式 Tuist 伺服器上的可用時長。

| 構件 | Air 與開放原始碼 | Pro | Enterprise |
| --- | --- | --- | --- |
| 快取構件，包括 Xcode 快取、模組快取、Gradle 快取、Bazel 遠端快取檔案，以及來自 Tuist Runners 的 GitLab CI 快取封存 | 14 天 | 30 天 | 30 天 |
| App Preview 建置與圖示 | 30 天 | 30 天 | 30 天 |
| 建置封存 | 7 天 | 30 天 | 30 天 |
| 執行構件，包括結果套件與工作階段封存 | 7 天 | 30 天 | 30 天 |
| 測試執行附件 | 30 天 | 30 天 | 30 天 |
| 分片套件 | 7 天 | 14 天 | 30 天 |

有效的帳戶方案決定託管保留期間。若帳戶沒有有效訂閱，Tuist 將使用 Air 保留期間。部分構件類型採用較短的期間，因為預期會重新產生。

在 Tuist 記錄測試執行識別碼之前建立的測試附件，不會納入自動刪除。在保留清理期間，Tuist 會避免無上限的歷史擁有權查詢，因此這些檔案仍保持可用。

### 自託管實例 {#self-hosted-artifact-files}

自託管構件清理為選擇性啟用，可依構件類型分別設定，且不受 30 天上限限制。請參閱<.localized_link href="/guides/server/self-host/server#artifact-retention">自託管構件保留設定</.localized_link>，了解支援的構件類型與部署選項。

## 儀表板與活動資料 {#dashboard-and-activity-data}

儀表板與活動記錄的保留政策獨立於構件檔案清理。以下期間不因託管方案而異，包括 Enterprise。

### Xcode 建置與測試洞察 {#xcode-build-and-test-insights}

核心 Xcode 建置與測試記錄目前沒有固定的時間基礎刪除排程。其他報告資料（例如時間軸步驟與機器指標）則有獨立的到期規則：

| 資料 | 保留期間 |
| --- | --- |
| 建置摘要、每檔案與每目標建置記錄，以及建置問題 | 沒有固定的時間基礎刪除排程 |
| 測試執行、模組與套件結果，以及個別測試結果 | 沒有固定的時間基礎刪除排程 |
| 建置時間軸步驟及其擷取的日誌 | 90 天 |
| 建置機器指標 | 90 天 |
| Xcode 專案圖譜記錄 | 30 天 |

這些記錄獨立於[構件檔案保留期間](#hosted-artifact-files)所涵蓋的可下載建置封存、結果套件與測試附件。在 Enterprise 方案中，這些檔案會保留 30 天；相關建置與測試記錄在檔案過期後仍保持可用。沒有固定時間基礎刪除排程的記錄並不保證永久可用。

### 其他儀表板與活動資料 {#other-dashboard-and-activity-data}

| 資料 | 保留期間 |
| --- | --- |
| Gradle 建置記錄、工作記錄、快取事件記錄、Mix 建置記錄、編譯檔案記錄、建置步驟記錄與診斷、Cargo 建置記錄（包括彙總編譯快取測量）與編譯器觀察、Bazel 叫用、Bazel 追蹤設定檔、已索引的設定檔步驟與動作診斷、待處理的 Bazel 設定檔與測試匯入記錄、Bazel 叫用日誌，以及 Bazel 遠端動作快取觀察 | 90 天 |
| 持續性模組詳細資訊頁面上的 Xcode 模組編譯與快取歷史 | 30 天 |
| 持續性詳細資訊頁面上的工作、宣告的 Once 動作、Bazel BEP 動作、編譯檔案與模組觀察 | 90 天，上述 Xcode 模組除外 |
| 持續性工作/動作/模組/檔案身分中繼資料 | 365 天內無觀察 |
| Runner 工作日誌、歸檔的 Runner 日誌，以及 Runner 工作機器指標 | 90 天 |
| Webhook 傳遞歷史 | 沒有固定的刪除排程 |

持續性詳細資訊 URL 不依賴特定建置保持可用。其身分辨識中繼資料可能比個別觀察更長久，因此詳細資訊頁面在所選期間內可能沒有歷史記錄。新歷史記錄是從功能部署後收到的報告中建置索引；現有的執行層級歷史記錄不會回溯複製。

ClickHouse 的內部 `system.*` 運作日誌資料表是在 ClickHouse 層級設定，而非由 Tuist 的產品資料保留政策管理。預設情況下它們沒有上限；隨附的自託管 Docker Compose 與內嵌 Helm ClickHouse 設定可以限制它們，詳情請參閱<.localized_link href="/guides/server/self-host/server#capping-operational-log-retention">限制運作日誌保留</.localized_link>。
