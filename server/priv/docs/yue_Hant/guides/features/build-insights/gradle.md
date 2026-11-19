---
{
  "title": "Gradle 構建洞察",
  "titleTemplate": ":title · 構建洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 儀表板中追蹤 Gradle 任務耗時同快取行為。"
}
---
# Gradle 建置洞察 {#gradle-build-insights}

Tuist 嘅 Gradle 外掛程式可以將建置分析數據傳送到 Tuist，讓你清晰了解任務執行同建置效能。

## 設定上傳行為 {#configure-upload-behavior}

預設情況下：
- 本地建置嘅分析數據會喺背景上傳。
- CI 運行嘅分析數據會喺前景上傳，以避免喺短暫存在嘅代理上遺失遙測數據。

你可以透過喺 `tuist` 擴展中使用 `uploadInBackground` 來控制此行為：

```kotlin
tuist {
    uploadInBackground = false // always upload in the foreground
}
```

## 設定參考 {#configuration-reference}

`uploadInBackground` 選項可喺 `settings.gradle.kts` 入面嘅 `tuist` 擴展區塊中設定：

| 選項 | 類型 | 預設值 | 描述 |
| --- | --- | --- | --- |
| `uploadInBackground` | `Boolean?` | `null`（本地背景，CI 前景） | 是否喺本地建置時於背景上傳建置洞察。 |

此設定唔會影響 `buildCache` 區塊中嘅遠端快取設定。

## 報告參與者聲明 {#report-actor-claim}

只有當你明確將 `TUIST_ACTOR_ID` 設定為組織範圍標籤，或喺設定中配置 `buildInsights.actorId` 時，建置同測試報告請求才會包含可選嘅 `x-tuist-actor-id` 標頭。預設情況下唔會傳送任何標籤，外掛程式亦唔會偵測作業系統用戶名。環境變數覆寫具有優先權。將任一覆寫設定為空字串以省略報告嘅識別碼；這並唔會移除由個人憑證建立嘅身份。無效嘅覆寫會省略聲明而唔會回退。如果自訂代理拒絕不熟悉嘅標頭，請使用 `TUIST_ACTOR_ID=""` 退出。

```kotlin
tuist {
    buildInsights {
        actorId = providers.environmentVariable("CORPORATE_ACTOR_ID").getOrElse("")
    }
}
```

參與者識別碼係 1–128 位元組嘅非空格可列印 ASCII 字符。任何可以檢視專案報告嘅人都可以看到佢哋，包括當專案公開時嘅公眾檢視者，並且會隨報告一併匯出。唔好包含你唔想公開嘅機密或個人資料。經驗證嘅個人憑證喺儀表板中具有優先權；客戶端傳送嘅識別碼否則會明確標示為 **未經驗證**。佢哋永遠唔會授予權限或自動連結到 Tuist 用戶。舊伺服器會忽略歸因標頭，而新伺服器繼續接受沒有該標頭嘅舊客戶端。沒有識別碼嘅新共享令牌報告會顯示 **未知**，而唔係發布組織；歷史報告會保留其先前嘅歸因。建置同測試列表會將已驗證用戶過濾器同未經驗證嘅報告識別碼過濾器分開。

## 網絡可信發布 {#network-trusted-publishing}

自託管部署可以明確允許來自其可信網絡嘅 Gradle 建置同測試報告，而無需開發者憑證。營運者必須先喺實例上配置 `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` 並重新啟動。這適用於每個受支援嘅專案；儀表板中沒有相關設定。請參閱 <.localized_link href="/guides/server/self-host/server#network-trusted-access">自託管指南</.localized_link>。

喺儲存庫中一次性設定目的地：

```kotlin
tuist {
    project = "organization/project"
    url = "https://tuist.internal.example"
    buildCache { enabled = false }
}
```

建置同測試報告唔需要經過身份驗證嘅快取端點發現。除非實例單獨啟用網絡可信快取訪問或開發者提供令牌，否則請禁用快取。未經簽名嘅測試報告會省略分片同現有建置參考，並且唔會驅動隔離或波動自動化。當確實缺少憑證時，會跳過隔離查找；如果有有效憑證，則保留現有嘅已驗證行為。如果存在憑證，仍然會使用佢哋，而無效憑證會失敗而唔會回退到無憑證發布。當缺少憑證時，外掛程式會自動發現自託管伺服器是否允許無憑證報告。唔需要客戶端標誌或 `buildInsights` 設定。喺升級無憑證客戶端之前，請將每個伺服器副本升級到支援發現功能嘅版本。沒有發現功能嘅舊伺服器、禁用嘅實例同發現錯誤仍然需要身份驗證；已驗證發布保持兼容。明確設定為空嘅 `TUIST_TOKEN` 會導致失敗關閉，而唔會啟用無憑證發布。對於沒有機密嘅 fork 或 Dependabot 作業，請刪除該變數而唔係將其定義為空字串。

伺服器會分配無憑證報告 ID。重複提交可能會創建第二個報告；此模式唔保證冪等重試或與已驗證測試報告嘅關聯。此類報告唔能觸發 VCS 評論或自動故障代理事件。網絡訪問係發布信任邊界，而唔係證明報告參與者身份嘅證據。

## 自訂元數據 {#custom-metadata}

將標籤同鍵值數據附加到 Gradle 建置，以比較來自不同團隊、硬件或工作流嘅運行。標籤可用作儀表板過濾器，值會顯示喺每個建置嘅詳細頁面以及應用程式編程介面同模型上下文協議工具中。

使用環境變數設定元數據：

```sh
export TUIST_BUILD_TAGS="nightly,android"
export TUIST_BUILD_VALUE_TICKET="TUIST-123"
export TUIST_BUILD_VALUE_RUNNER="macos-14"
```

你亦可以喺 `settings.gradle.kts` 中配置元數據：

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

當同一值喺兩處都配置時，`settings.gradle.kts` 中嘅值具有優先權。

標籤只能包含字母、數字、連字符同下劃線。一個建置最多可以有 50 個標籤，每個標籤最多可以包含 50 個字符。一個建置最多可以有 20 個鍵值條目，每個鍵最多可以包含 50 個字符，每個值最多可以包含 500 個字符。這些同用於 Xcode 建置元數據嘅伺服器端限制相同。外掛程式喺發送報告之前會跳過無效標籤同過大或空嘅元數據條目，因此無效配置唔會阻止其餘建置洞察報告被儲存。對於唔符合標籤約束嘅值，請使用鍵值元數據。

自訂元數據對專案成員喺儀表板、應用程式編程介面同模型上下文協議工具中可見。唔好將其用於憑證、訪問令牌或其他敏感數據。Tuist 會保留 Gradle 建置數據（包括此元數據）90 天。詳情請參閱 <.localized_link href="/guides/server/data-retention">數據保留政策</.localized_link>。

## 失敗詳情 {#failure-details}

當建置失敗時，外掛程式會報告每個失敗任務或配置步驟失敗嘅原因：即 Gradle 控制台打印嘅異常訊息及其原因鏈，例如失敗嘅 `compileJava` 任務嘅編譯器錯誤或建置腳本中嘅錯誤。唔會收集堆疊追蹤同任務輸出。外掛程式喺發送報告之前會將專案內嘅路徑轉換為相對路徑，而 Tuist 會遮蔽佢識別到嘅憑證同其他本地路徑。每條訊息限制為 16 KiB，一個建置最多保留 32 個失敗步驟嘅訊息。

失敗訊息可透過應用程式編程介面、模型上下文協議工具（`get_gradle_build`、`list_gradle_build_tasks` 同 `get_gradle_build_step`）以及 CLI 供專案成員查看：

```bash
tuist build gradle failure list <build-id>
```

訊息可以包含原始碼片段同專案詳情。透過 [網絡信任發布](#network-trusted-publishing) 在無憑證情況下發布嘅報告唔會包含呢啲內容。Tuist 會將呢啲內容連同其餘 Gradle 建置數據保留 90 天。
