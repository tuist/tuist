---
{
  "title": "Gradle 建構分析",
  "titleTemplate": ":title · 建構分析 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 儀表板中追蹤 Gradle 任務耗時與快取行為。"
}
---
# Gradle 建構洞察 {#gradle-build-insights}

Tuist 嘅 Gradle 外掛程式可以將建構分析數據傳送到 Tuist，讓你清楚了解任務執行同建構效能。

## 設定上傳行為 {#configure-upload-behavior}

預設情況下：
- 本地建構嘅分析數據會喺背景上傳。
- CI 運行嘅分析數據會喺前景上傳，以免喺短暫存在嘅代理上遺失遙測數據。

你可以透過 `tuist` 擴展中嘅 `uploadInBackground` 來控制呢個行為：

```kotlin
tuist {
    uploadInBackground = false // always upload in the foreground
}
```

## 設定參考 {#configuration-reference}

`uploadInBackground` 選項可喺 `settings.gradle.kts` 入面嘅 `tuist` 擴展區塊中使用：

| 選項 | 類型 | 預設值 | 描述 |
| --- | --- | --- | --- |
| `uploadInBackground` | `Boolean?` | `null`（本地背景，CI 前景） | 是否喺本地建構時以背景方式上傳建構洞察。 |

呢個設定唔會影響 `buildCache` 區塊中嘅遠端快取設定。

## 報告參與者聲明 {#report-actor-claim}

只有當你明確將 `TUIST_ACTOR_ID` 設定為組織範圍標籤，或者喺設定中配置 `buildInsights.actorId` 時，建構同測試報告請求先會包含可選嘅 `x-tuist-actor-id` 標頭。預設情況下唔會發送任何標籤，外掛程式亦都唔會偵測作業系統用戶名。環境變數覆寫具有優先權。將任一覆寫設定為空字串以省略報告嘅識別碼；這並唔會移除由個人憑證建立嘅身份。無效嘅覆寫會省略聲明而唔會回退。如果自訂代理拒絕不熟悉嘅標頭，請使用 `TUIST_ACTOR_ID=""` 退出。

```kotlin
tuist {
    buildInsights {
        actorId = providers.environmentVariable("CORPORATE_ACTOR_ID").getOrElse("")
    }
}
```

參與者識別碼係 1–128 字節嘅非空格可打印 ASCII 字符。任何可以查看項目報告嘅人都可以看到佢哋，包括項目公開時嘅公眾觀看者，並且會隨報告一併匯出。唔好包含你唔想公開嘅機密或個人資料。經驗證嘅個人憑證喺儀表板中具有優先權；客戶端發送嘅識別碼否則會明確標示為 **未經驗證**。佢哋永遠唔會授予權限或自動連結到 Tuist 用戶。舊伺服器會忽略歸因標頭，而新伺服器會繼續接受沒有該標頭嘅舊客戶端。沒有識別碼嘅新共享令牌報告會顯示 **未知**，而唔係發布組織；歷史報告會保留其先前嘅歸因。建構同測試列表會將已驗證用戶過濾器同未經驗證嘅報告識別碼過濾器分開。

## 網絡可信發布 {#network-trusted-publishing}

自託管部署可以明確允許來自其可信網絡嘅 Gradle 建構同測試報告，而無需開發者憑證。營運者必須首先喺實例上配置 `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` 並重新啟動。這適用於每個受支持嘅項目；儀表板中沒有相關設定。請參閱 <.localized_link href="/guides/server/self-host/server#network-trusted-access">自託管指南</.localized_link>。

喺儲存庫中一次性配置目標：

```kotlin
tuist {
    project = "organization/project"
    url = "https://tuist.internal.example"
    buildCache { enabled = false }
}
```

建構同測試報告唔需要經過認證嘅快取端點發現。除非實例單獨啟用網絡可信快取訪問或開發者提供令牌，否則請禁用快取。未簽名嘅測試報告會省略分片同現有建構引用，並且唔會驅動隔離或不穩定性自動化。當憑證確實缺失時，會跳過隔離查找；如果有有效憑證，則保留現有嘅認證行為。如果存在憑證，仍然會使用佢哋，無效憑證會失敗而唔會回退到無憑證發布。當缺少憑證時，外掛程式會自動發現自託管伺服器是否允許無憑證報告。唔需要客戶端標誌或 `buildInsights` 設定。喺升級無憑證客戶端之前，請將每個伺服器副本升級到支持發現嘅版本。較舊嘅沒有發現功能嘅伺服器、禁用嘅實例同發現錯誤仍然需要認證；認證發布保持兼容。明確為空嘅 `TUIST_TOKEN` 會導致失敗關閉，而唔係啟用無憑證發布。對於沒有秘密嘅 fork 或 Dependabot 作業，請刪除該變量而唔係將其定義為空字串。

伺服器會分配無憑證報告 ID。重複提交可能會創建第二份報告；此模式唔保證冪等重試或與認證測試報告嘅關聯。此類報告無法觸發 VCS 評論或自動故障代理事件。網絡訪問係發布信任邊界，而唔係報告參與者身份嘅證明。

## 自訂元數據 {#custom-metadata}

將標籤同鍵值數據附加到 Gradle 建構，以比較來自不同團隊、硬件或工作流嘅運行。標籤可用作儀表板過濾器，值會顯示喺每個建構嘅詳情頁面以及應用程式編程接口同 Model Context Protocol 工具中。

使用環境變數設定元數據：

```sh
export TUIST_BUILD_TAGS="nightly,android"
export TUIST_BUILD_VALUE_TICKET="TUIST-123"
export TUIST_BUILD_VALUE_RUNNER="macos-14"
```

你亦都可以喺 `settings.gradle.kts` 中配置元數據：

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

標籤只能包含字母、數字、連字號同下劃線。一個建構最多可以有 50 個標籤，每個標籤最多可以包含 50 個字符。一個建構最多可以有 20 個鍵值條目，每個鍵最多可以包含 50 個字符，每個值最多可以包含 500 個字符。這些同用於 Xcode 建構元數據嘅伺服器端限制相同。外掛程式喺發送報告之前會跳過無效標籤同過大或空嘅元數據條目，因此無效配置唔會阻止剩餘嘅建構洞察報告被存儲。對於唔符合標籤約束嘅值，請使用鍵值元數據。

項目成員可以喺儀表板以及透過應用程式編程接口同 Model Context Protocol 工具中看到自訂元數據。唔好將其用於憑證、訪問令牌或其他敏感數據。Tuist 會保留 Gradle 建構數據（包括此元數據）90 天。詳情請參閱 <.localized_link href="/guides/server/data-retention">數據保留政策</.localized_link>。
