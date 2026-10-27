---
{
  "title": "Gradle Build Insights",
  "titleTemplate": ":title · Build Insights · Features · Guides · Tuist",
  "description": "Track Gradle task timings and cache behavior in the Tuist dashboard."
}
---
# Gradle 建構洞察 {#gradle-build-insights}

Tuist 的 Gradle 外掛程式可以將建構分析資料傳送到 Tuist，讓你清楚了解任務執行與建構效能。

## 設定上傳行為 {#configure-upload-behavior}

預設情況下：
- 本機建構的建構分析資料會在背景上傳。
- CI 執行的建構分析資料會在前台上傳，以避免在短暫存在的代理程式上遺失遙測資料。

你可以使用 `tuist` 擴充功能中的 `uploadInBackground` 來控制此行為：

```kotlin
tuist {
    uploadInBackground = false // always upload in the foreground
}
```

## 設定參考 {#configuration-reference}

`tuist` 擴充功能區塊（位於 `settings.gradle.kts`）中提供 `uploadInBackground` 選項：

| 選項 | 類型 | 預設值 | 說明 |
| --- | --- | --- | --- |
| `uploadInBackground` | `Boolean?` | `null`（本機為背景，CI 為前台） | 是否在本機建構時於背景上傳建構洞察資料。 |

此設定不會影響 `buildCache` 區塊中的遠端快取設定。

## 回報參與者聲明 {#report-actor-claim}

只有在將 `TUIST_ACTOR_ID` 明確設定為組織範圍標籤，或在設定中設定 `buildInsights.actorId` 時，建構與測試回報請求才會包含可選的 `x-tuist-actor-id` 標頭。預設不會傳送任何標籤，且外掛程式不會偵測作業系統使用者名稱。環境變數覆寫具有優先權。將任一覆寫設為空字串以省略回報的識別碼；這不會移除由個別憑證建立的身分。無效的覆寫會省略聲明，而不會退回。如果自訂 Proxy 拒絕不熟悉的標頭，請使用 `TUIST_ACTOR_ID=""` 選擇退出。

```kotlin
tuist {
    buildInsights {
        actorId = providers.environmentVariable("CORPORATE_ACTOR_ID").getOrElse("")
    }
}
```

參與者識別碼為 1–128 位元組的非空格可列印 ASCII 字元。任何可以檢視專案報告的人都能看到它們，包括專案公開時的公眾檢視者，並且會隨報告匯出。請勿包含你不想公開的機密或個人資訊。經驗證的個別憑證在儀表板中具有優先權；否則由用戶端傳送的識別碼會明確標示為 **未經驗證**。它們永遠不會授予權限或自動連結到 Tuist 使用者。舊版伺服器會忽略歸因標頭，而新版伺服器仍會接受沒有該標頭的舊版用戶端。沒有識別碼的新共用權杖報告會顯示 **未知**，而非發佈組織；歷史報告會保留其先前的歸因。建構與測試清單會將已驗證使用者篩選器與未經驗證的回報識別碼篩選器分開。

## 網路信任發佈 {#network-trusted-publishing}

自行託管部署可以明確允許來自其信任網路的 Gradle 建構與測試報告，無需開發人員憑證。營運者必須先在實例上設定 `TUIST_NETWORK_TRUSTED_REPORT_PUBLISHING=true` 並重新啟動。這適用於每個支援的專案；儀表板中沒有相關設定。請參閱 <.localized_link href="/guides/server/self-host/server#network-trusted-report-publishing">自行託管指南</.localized_link>。

在儲存庫中設定一次目的地：

```kotlin
tuist {
    project = "organization/project"
    url = "https://tuist.internal.example"
    buildCache { enabled = false }
}
```

建構與測試回報不需要經過身分驗證的快取端點探索。存取快取仍然需要憑證：如果開發人員未佈建權杖，請停用快取。未簽章的測試報告會省略分片與現有建構參考，且不會驅動隔離或不穩定性自動化。當確實缺少憑證時，會跳過隔離查詢；使用有效憑證時，會保留現有的已驗證行為。如果存在憑證，仍會使用它們，且無效憑證會失敗，而不會退回至免憑證發佈。當缺少憑證時，外掛程式會自動探索自行託管伺服器是否允許免憑證回報。不需要用戶端旗標或 `buildInsights` 設定。在升級免憑證用戶端之前，請將每個伺服器副本升級至支援探索的版本。不支援探索的舊版伺服器、停用的實例以及探索錯誤仍然需要身分驗證；已驗證的發佈保持相容。明確為空的 `TUIST_TOKEN` 會導致失敗關閉，而不會啟用免憑證發佈。對於沒有機密的分支或 Dependabot 工作，請移除該變數，而不是將其定義為空字串。

伺服器會指派免憑證報告 ID。重複提交可能會建立第二份報告；此模式不保證冪等重試或與已驗證測試報告的關聯。此類報告無法觸發 VCS 註解或自動失敗代理事件。網路存取是發佈的信任邊界，並非所回報參與者身分的證明。

## 自訂中繼資料 {#custom-metadata}

將標籤與鍵值資料附加到 Gradle 建構，以比較來自不同團隊、硬體或工作流程的執行結果。標籤可用作儀表板篩選器，值會出現在每個建構的詳細頁面以及應用程式介面和 Model Context Protocol 工具中。

使用環境變數設定中繼資料：

```sh
export TUIST_BUILD_TAGS="nightly,android"
export TUIST_BUILD_VALUE_TICKET="TUIST-123"
export TUIST_BUILD_VALUE_RUNNER="macos-14"
```

你也可以在 `settings.gradle.kts` 中設定中繼資料：

```kotlin
tuist {
    buildInsights {
        tag("nightly")
        tag("android")
        value("ticket", "TUIST-123")
        value("runner", "macos-14")
    }
}
```

當兩處都設定了相同的值時，`settings.gradle.kts` 中的值具有優先權。

標籤只能包含字母、數字、連字號和底線。一個建構最多可以有 50 個標籤，每個標籤最多可以包含 50 個字元。一個建構最多可以有 20 個鍵值項目，每個鍵最多可以包含 50 個字元，每個值最多可以包含 500 個字元。這些與用於 Xcode 建構中繼資料的伺服器端限制相同。外掛程式在傳送報告之前會跳過無效標籤以及過大或空的中繼資料項目，因此無效設定不會阻止其餘建構洞察報告被儲存。對於不符合標籤約束的值，請使用鍵值中繼資料。

自訂中繼資料在儀表板中對專案成員可見，並可透過應用程式介面和 Model Context Protocol 工具存取。請勿將其用於憑證、存取權杖或其他敏感資料。Tuist 會保留 Gradle 建構資料（包括此中繼資料）90 天。詳情請參閱 <.localized_link href="/guides/server/data-retention">資料保留政策</.localized_link>。
