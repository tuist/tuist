---
{
  "title": "Gradle 建置洞察",
  "titleTemplate": ":title · 建置洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 儀表板追蹤 Gradle 任務耗時與快取行為。"
}
---
# Gradle 建構洞察 {#gradle-build-insights}

Tuist 的 Gradle 外掛程式可以將建構分析資料傳送至 Tuist，讓你清楚了解工作執行與建構效能。

## 設定上傳行為 {#configure-upload-behavior}

預設情況下：
- 本機建構的建構分析資料會在背景上傳。
- CI 執行的建構分析資料會在前台上傳，以避免在短暫存活的代理程式上遺失遙測資料。

你可以使用 `uploadInBackground` 內的 `tuist` 擴充功能來控制此行為：

```kotlin
tuist {
    uploadInBackground = false // always upload in the foreground
}
```

## 設定參考 {#configuration-reference}

`uploadInBackground` 選項可在 `tuist` 的 `settings.gradle.kts` 擴充區塊中使用：

| 選項 | 類型 | 預設值 | 說明 |
| --- | --- | --- | --- |
| `uploadInBackground` | `Boolean?` | `null`（本機為背景，CI 為前台） | 是否在本機建構時於背景上傳建構洞察資料。 |

此設定不會影響 `buildCache` 區塊中的遠端快取設定。

## 回報參與者聲明 {#report-actor-claim}

只有當你明確將 `TUIST_ACTOR_ID` 設定為組織範圍的標籤，或在設定中設定 `buildInsights.actorId` 時，建構與測試報告請求才會包含可選的 `x-tuist-actor-id` 標頭。預設不會傳送任何標籤，且外掛程式不會偵測作業系統使用者名稱。環境覆寫具有優先權。將任一覆寫設為空字串以省略所回報的識別碼；這不會移除由個別憑證建立的身分。無效的覆寫會省略聲明，而非退回預設行為。如果自訂 Proxy 拒絕不熟悉的標頭，請使用 `TUIST_ACTOR_ID=""` 選擇退出。

```kotlin
tuist {
    buildInsights {
        actorId = providers.environmentVariable("CORPORATE_ACTOR_ID").getOrElse("")
    }
}
```

參與者識別碼為 1–128 位元組的非空格可列印 ASCII 字元。任何能檢視專案報告的人都能看到這些識別碼，包括專案公開時的公開檢視者，並且會隨報告匯出。請勿包含你不希望公開的機密或個人資訊。經驗證的個別憑證在儀表板中具有優先權；否則由用戶端傳送的識別碼會明確標示為 **未經驗證**。它們從不會授予權限或自動連結至 Tuist 使用者。舊版伺服器會忽略歸因標頭，而新版伺服器繼續接受沒有該標頭的舊版用戶端。沒有識別碼的新共用權杖報告會顯示 **未知**，而非發布組織；歷史報告則保留其先前的歸因。建構與測試清單會將已驗證使用者篩選器與未經驗證的回報識別碼篩選器分開。

## 網路信任發布 {#network-trusted-publishing}

自行託管的部署可以明確允許來自其信任網路的 Gradle 建構與測試報告，無需開發人員憑證。營運人員必須先在實例上設定 `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` 並重新啟動。這適用於每個受支援的專案；儀表板中沒有相關設定。請參閱 <.localized_link href="/guides/server/self-host/server#network-trusted-access">自行托管指南</.localized_link>。

在儲存庫中設定一次目的地：

```kotlin
tuist {
    project = "organization/project"
    url = "https://tuist.internal.example"
    buildCache { enabled = false }
}
```

建構與測試報告不需要經過驗證的快取端點探索。除非實例另行啟用網路信任快取存取，或開發人員提供權杖，否則請停用快取。未簽名的測試報告會省略分片與現有建構參考，且不會驅動隔離或不穩定性自動化。當憑證確實不存在時，會跳過隔離查詢；若有有效憑證，則保留現有的驗證行為。如果存在憑證，仍會使用它們，而無效憑證會失敗，而非退回至免憑證發布。當憑證不存在時，外掛程式會自動探索自行托管伺服器是否允許免憑證報告。不需要用戶端旗標或 `buildInsights` 設定。在升級免憑證用戶端之前，請將每個伺服器副本升級至支援探索的版本。較舊的沒有探索功能的伺服器、已停用的實例以及探索錯誤仍然需要驗證；驗證發布保持相容。明確設為空的 `TUIST_TOKEN` 會導致失敗關閉，而非啟用免憑證發布。對於沒有機密的分支或 Dependabot 工作，請移除該變數，而非將其定義為空字串。

伺服器會指派免憑證報告 ID。重複提交可能會建立第二份報告；此模式不保證冪等重試或與驗證測試報告的關聯。此類報告無法觸發 VCS 註解或自動失敗代理事件。網路存取是發布的信任邊界，並非所回報參與者身分的證明。

## 自訂中繼資料 {#custom-metadata}

將標籤與鍵值資料附加至 Gradle 建構，以比較來自不同團隊、硬體或工作流程的執行。標籤可用作儀表板篩選器，值則出現在每個建構的詳細頁面，以及應用程式介面和 Model Context Protocol 工具中。

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

當兩處都設定相同的值時，`settings.gradle.kts` 中的值具有優先權。

標籤只能包含字母、數字、連字號和下底線。一個建構最多可以有 50 個標籤，每個標籤最多可以包含 50 個字元。一個建構最多可以有 20 個鍵值項目，每個鍵最多可以包含 50 個字元，每個值最多可以包含 500 個字元。這些與用於 Xcode 建構中繼資料的伺服器端限制相同。外掛程式在發送報告之前會跳過無效標籤以及過大或空的中繼資料項目，因此無效設定不會阻止其餘建構洞察報告被儲存。對於不符合標籤約束的值，請使用鍵值中繼資料。

自訂中繼資料對專案成員在儀表板、應用程式介面和 Model Context Protocol 工具中可見。請勿將其用於憑證、存取權杖或其他敏感資料。Tuist 會保留 Gradle 建構資料（包括此中繼資料）90 天。詳情請參閱 <.localized_link href="/guides/server/data-retention">資料保留政策</.localized_link>。

## 失敗詳細資料 {#failure-details}

當建構失敗時，外掛程式會報告每個失敗任務或設定步驟的失敗原因：即 Gradle 主控台列印的例外訊息及其因果鏈，例如失敗的 `compileJava` 任務的編譯器錯誤或建構腳本中的錯誤。系統不會收集堆疊追蹤和任務輸出。外掛程式在發送報告前會將專案內的路徑轉為相對路徑，而 Tuist 會遮蔽其識別的憑證和其他本機路徑。每則訊息限制為 16 KiB，且一個建構最多保留 32 個失敗步驟的訊息。

失敗訊息可透過應用程式介面、Model Context Protocol 工具（`get_gradle_build`、`list_gradle_build_tasks` 和 `get_gradle_build_step`）以及 CLI 供專案成員檢視：

```bash
tuist build gradle failure list <build-id>
```

訊息可能包含原始碼片段和專案詳細資料。透過 [網路信任發布](#network-trusted-publishing) 且在無憑證情況下發布的報告不會包含這些內容。Tuist 會將它們與其餘 Gradle 建構資料一同保留 90 天。
