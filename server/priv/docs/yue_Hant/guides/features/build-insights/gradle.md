---
{
  "title": "Gradle 構建洞察",
  "titleTemplate": ":title · 構建洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 儀表板中追蹤 Gradle 任務耗時同快取行為。"
}
---
# Gradle 構建洞察 {#gradle-build-insights}

Tuist 嘅 Gradle 外掛程式可以將構建分析數據發送到 Tuist，讓你清晰了解任務執行同構建性能。

## 配置上傳行為 {#configure-upload-behavior}

預設情況下：
- 本地構建嘅分析數據會喺後台上傳。
- CI 運行嘅分析數據會喺前台上傳，以避免喺短暫存在嘅代理上遺失遙測數據。

你可以透過喺 `tuist` 擴展中使用 `uploadInBackground` 嚟控制呢種行為：

```kotlin
tuist {
    uploadInBackground = false // always upload in the foreground
}
```

## 配置參考 {#configuration-reference}

`uploadInBackground` 選項可用於 `settings.gradle.kts` 中嘅 `tuist` 擴展塊：

| 選項 | 類型 | 預設值 | 描述 |
| --- | --- | --- | --- |
| `uploadInBackground` | `Boolean?` | `null`（本地後台，CI 前台） | 是否喺後台為本地構建上傳構建洞察。 |

此設置不會影響 `buildCache` 塊中嘅遠程緩存設置。

## 報告參與者聲明 {#report-actor-claim}

只有當你明確將 `TUIST_ACTOR_ID` 設置為組織範圍嘅標籤，或者喺你嘅設置中配置 `buildInsights.actorId` 時，構建同測試報告請求才會包含可選嘅 `x-tuist-actor-id` 標頭。預設情況下不會發送任何標籤，而且外掛程式不會檢測操作系統用戶名。環境覆蓋具有優先權。將任一覆蓋設置為空字符串以省略報告嘅標識符；這不會刪除由個人憑證建立嘅身份。無效嘅覆蓋會省略聲明而唔係回退。如果自定義代理拒絕不熟悉嘅標頭，請使用 `TUIST_ACTOR_ID=""` 退出。

```kotlin
tuist {
    buildInsights {
        actorId = providers.environmentVariable("CORPORATE_ACTOR_ID").getOrElse("")
    }
}
```

參與者標識符係 1–128 字節嘅非空格可打印 ASCII 字符。任何可以查看項目報告嘅人都可以看到佢哋，包括項目公開時嘅公眾觀眾，並且會隨報告一齊導出。唔好包含你唔想公開嘅機密或個人信息。經驗證嘅個人憑證喺儀表板中具有優先權；否則客戶端發送嘅標識符會明確顯示為 **未經驗證**。佢哋永遠唔會授予權限或自動鏈接到 Tuist 用戶。舊服務器會忽略歸因標頭，而新服務器繼續接受沒有該標頭嘅舊客戶端。沒有標識符嘅新共享令牌報告會顯示 **未知**，而唔係發布組織；歷史報告保留其先前嘅歸因。構建同測試列表將經驗證用戶過濾器同未經驗證報告標識符過濾器分開。

## 網絡信任發布 {#network-trusted-publishing}

自託管部署可以明確允許來自其受信任網絡嘅 Gradle 構建同測試報告，而無需開發者憑證。運營商必須先喺實例上配置 `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` 並重新啟動。這適用於每個受支持嘅項目；儀表板中沒有相關設置。請參閱 <.localized_link href="/guides/server/self-host/server#network-trusted-access">自託管指南</.localized_link>。

喺存儲庫中一次性配置目標：

```kotlin
tuist {
    project = "organization/project"
    url = "https://tuist.internal.example"
    buildCache { enabled = false }
}
```

構建同測試報告唔需要經過身份驗證嘅緩存端點發現。除非實例單獨啟用網絡信任緩存訪問或者開發者提供令牌，否則請禁用緩存。未簽名嘅測試報告會省略分片同現有構建引用，並且唔會驅動隔離或 flakiness 自動化。當憑證確實缺失時，會跳過隔離查找；如果有有效憑證，則保留現有嘅已驗證行為。如果存在憑證，仍然會使用佢哋，無效憑證會失敗而唔會回退到無憑證發布。當缺少憑證時，外掛程式會自動發現自託管服務器是否允許無憑證報告。唔需要客戶端標誌或 `buildInsights` 設置。喺升級無憑證客戶端之前，請將每個服務器副本升級到支持發現嘅版本。較舊嘅沒有發現功能嘅服務器、禁用嘅實例同發現錯誤仍然需要身份驗證；已驗證發布保持兼容。顯式為空嘅 `TUIST_TOKEN` 會導致失敗關閉，而唔係啟用無憑證發布。對於沒有秘密嘅 fork 或 Dependabot 作業，請刪除該變量而唔係將其定義為空字符串。

服務器分配無憑證報告 ID。重複提交可能會創建第二份報告；此模式唔保證冪等重試或與已驗證測試報告嘅關聯。此類報告無法觸發 VCS 評論或自動故障代理事件。網絡訪問係發布信任邊界，而唔係證明報告參與者身份嘅證據。

## 自定義元數據 {#custom-metadata}

將標籤同鍵值數據附加到 Gradle 構建，以便比較來自不同團隊、硬件或工作流嘅運行。標籤可用作儀表板過濾器，值會顯示喺每個構建嘅詳細頁面以及應用程序編程接口同 Model Context Protocol 工具中。

使用環境變量設置元數據：

```sh
export TUIST_BUILD_TAGS="nightly,android"
export TUIST_BUILD_VALUE_TICKET="TUIST-123"
export TUIST_BUILD_VALUE_RUNNER="macos-14"
```

你也可以喺 `settings.gradle.kts` 中配置元數據：

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

當同一個值喺兩個地方都配置時，`settings.gradle.kts` 中嘅值具有優先權。

標籤只能包含字母、數字、連字符同下劃線。一個構建最多可以有 50 個標籤，每個標籤最多可以包含 50 個字符。一個構建最多可以有 20 個鍵值條目，每個鍵最多可以包含 50 個字符，每個值最多可以包含 500 個字符。這些係與 Xcode 構建元數據使用嘅相同服務器端限制。外掛程式喺發送報告之前會跳過無效標籤同過大或空嘅元數據條目，因此無效配置唔會阻止剩餘構建洞察報告嘅存儲。對於唔符合標籤約束嘅值，請使用鍵值元數據。

項目成員可以喺儀表板中以及透過應用程序編程接口同 Model Context Protocol 工具看到自定義元數據。唔好將其用於憑證、訪問令牌或其他敏感數據。Tuist 會保留 Gradle 構建數據（包括此元數據）90 天。詳情請參閱 <.localized_link href="/guides/server/data-retention">數據保留政策</.localized_link>。
