---
{
  "title": "Gradle 建置分析",
  "titleTemplate": ":title · 建置分析 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 儀表板中追蹤 Gradle 任務耗時與快取行為。"
}
---
# Gradle 建置洞察 {#gradle-build-insights}

Tuist 的 Gradle 外掛程式可將建置分析資料傳送至 Tuist，讓你清楚掌握任務執行與建置效能。

## 設定上傳行為 {#configure-upload-behavior}

預設情況下：
- 本機建置的建置分析資料會在背景中上傳。
- CI 執行的建置分析資料會在前台上傳，以避免在短暫存活的代理程式上遺失遙測資料。

你可以使用 `uploadInBackground` 內的 `tuist` 擴充功能來控制此行為：

```kotlin
tuist {
    uploadInBackground = false // always upload in the foreground
}
```

## 設定參考 {#configuration-reference}

`uploadInBackground` 選項可在 `tuist` 中的 `settings.gradle.kts` 擴充區塊中使用：

| 選項 | 類型 | 預設值 | 說明 |
| --- | --- | --- | --- |
| `uploadInBackground` | `Boolean?` | `null`（本機背景上傳，CI 前台上傳） | 是否在本機建置時於背景中上傳建置洞察資料。 |

此設定不會影響 `buildCache` 區塊中的遠端快取設定。

## 回報參與者聲明 {#report-actor-claim}

只有在將 `TUIST_ACTOR_ID` 明確設為組織範圍的標籤，或在設定中設定 `buildInsights.actorId` 時，建置與測試回報請求才會包含選用標頭 `x-tuist-actor-id`。預設不會傳送任何標籤，且外掛程式不會偵測作業系統的使用者名稱。環境變數覆寫具有優先權。將任一覆寫設為空字串即可省略回報的識別碼；這不會移除由個別憑證建立的身分。無效的覆寫會省略該聲明，而非回退。如果自訂代理伺服器拒絕不熟悉的標頭，請使用 `TUIST_ACTOR_ID=""` 選擇退出。

```kotlin
tuist {
    buildInsights {
        actorId = providers.environmentVariable("CORPORATE_ACTOR_ID").getOrElse("")
    }
}
```

參與者識別碼為 1–128 位元組的非空格可列印 ASCII 字元。任何能檢視專案報告的人都能看到這些識別碼，包括專案公開時的公開檢視者，且它們會隨報告匯出。請勿包含你不願公開的機密或個人資訊。經驗證的個別憑證在儀表板中具有優先權；否則由用戶端傳送的識別碼會明確標示為**未經驗證**。它們永遠不會授予權限，也不會自動連結至 Tuist 使用者。舊版伺服器會忽略歸因標頭，而新版伺服器仍會接受沒有該標頭的舊版用戶端。沒有識別碼的新共用權杖報告會顯示**未知**，而非發布組織；歷史報告則保留其先前的歸因。建置與測試清單會將已驗證使用者的篩選條件與未經驗證的回報識別碼篩選條件分開。

## 網路信任發布 {#network-trusted-publishing}

自行託管的部署可以明確允許來自其信任網路的 Gradle 建置與測試報告，無需開發人員憑證。營運者必須先在實例上設定 `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` 並重新啟動。這適用於每個支援的專案；儀表板中沒有相關設定。請參閱<.localized_link href="/guides/server/self-host/server#network-trusted-access">自行托管指南</.localized_link>。

在儲存庫中一次性設定目的地：

```kotlin
tuist {
    project = "organization/project"
    url = "https://tuist.internal.example"
    buildCache { enabled = false }
}
```

建置與測試回報不需要經過身分驗證的快取端點探索。除非實例另行啟用網路信任的快取存取，或開發人員提供權杖，否則請停用快取。未簽章的測試報告會省略分片與現有建置參考，且不會觸發隔離或不穩定測試自動化。當確實缺少憑證時，會跳過隔離查詢；若有有效憑證，則保留現有的已驗證行為。若存在憑證，仍會使用它們，且無效憑證會導致失敗，而非回退到免憑證發布。當缺少憑證時，外掛程式會自動探索自行托管伺服器是否允許免憑證回報。不需要任何用戶端旗標或 `buildInsights` 設定。在升級免憑證用戶端之前，請將每個伺服器副本升級至支援探索的版本。不具備探索功能的舊版伺服器、已停用的實例，以及探索錯誤仍需要身分驗證；已驗證的發布仍保持相容。明確設為空的 `TUIST_TOKEN` 會以失敗收場，而非啟用免憑證發布。對於沒有機密的分支或 Dependabot 工作，請移除該變數，而非將其定義為空字串。

伺服器會指派免憑證的報告 ID。重複提交可能會建立第二份報告；此模式不保證冪等重試或與已驗證測試報告的關聯。這類報告無法觸發版本控制系統註解或自動失敗代理事件。網路存取是發布的信任邊界，並非證明所回報參與者的身分。

## 自訂中繼資料 {#custom-metadata}

為 Gradle 建置附加標籤與鍵值資料，以便比較來自不同團隊、硬體或工作流程的執行結果。標籤可作為儀表板篩選條件，值則會出現在每個建置的詳細頁面，以及應用程式介面與 Model Context Protocol 工具中。

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

標籤只能包含字母、數字、連字號與底線。一個建置最多可有 50 個標籤，每個標籤最多 50 個字元。一個建置最多可有 20 筆鍵值項目，每個鍵最多 50 個字元，每個值最多 500 個字元。這些限制與 Xcode 建置中繼資料使用的伺服器端限制相同。外掛程式在傳送報告前會略過無效標籤以及過大或空白的中繼資料項目，因此無效設定不會阻止其餘建置洞察報告被儲存。對於不符合標籤限制的値，請使用鍵值中繼資料。

專案成員可在儀表板、應用程式介面與 Model Context Protocol 工具中查看自訂中繼資料。請勿將其用於憑證、存取權杖或其他敏感資料。Tuist 會保留 Gradle 建置資料（包括此中繼資料）90 天。詳情請參閱<.localized_link href="/guides/server/data-retention">資料保留政策</.localized_link>。
