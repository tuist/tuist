---
{
  "title": "Grafana",
  "titleTemplate": ":title | 整合 | 指南 | Tuist",
  "description": "在 Grafana 中監控 Tuist 的建構健康狀況、耗時同快取節省情況，並為團隊設定警示。"
}
---

# Grafana 整合 {#grafana}

Tuist 數據源讓你可以喺 Grafana 使用構建、測試同緩存指標，包括耗時、失敗次數，以及由緩存節省嘅報告時間。圍繞你團隊關心嘅項目同指標建立儀表板，或者將 Tuist 指標同公司現有儀表板中嘅其他數據源結合。使用 Grafana 嘅警報規則同通知渠道，令你團隊知道何時構建變慢或失敗增加。

## 可用指標 {#metric-definitions}

表格列出可讀標籤同佢哋嘅查詢標識符。構建健康查詢使用 `metric` 字段中嘅標識符；構建同測試持續時間查詢選擇 `series` 字段中嘅 `average`、`p50`、`p90` 或 `p99`。

### 構建數量同可靠性

| 指標 | 標識符 | 測量內容 |
| --- | --- | --- |
| 構建數量 | `builds` | 記錄嘅構建數量。 |
| 成功構建 | `successful_builds` | 成功完成嘅構建。 |
| 失敗構建 | `failed_builds` | 失敗嘅構建。 |
| 已取消構建 | `cancelled_builds` | 記錄為已取消嘅構建。請參閱 [構建系統差異](#build-systems)。 |
| 構建成功率 | `success_rate` | 成功 ÷（成功 + 失敗），以百分比表示。 |
| 失敗或緩慢構建 | `builds_needing_attention` | 失敗或緩慢嘅構建，每個構建只計算一次。 |

### 構建同測試持續時間

| 指標 | 標識符 | 測量內容 |
| --- | --- | --- |
| 平均持續時間 | `average` | 所選運行嘅平均持續時間。 |
| 中位數持續時間 | `p50` | 運行持續時間嘅第 50 個百分位數。 |
| 第 90 個百分位數持續時間 | `p90` | 90% 嘅運行低於或等於此持續時間。 |
| 第 99 個百分位數持續時間 | `p99` | 99% 嘅運行低於或等於此持續時間。 |
| 緩慢構建閾值 | `slow_build_threshold` | 第 90 個百分位數持續時間，或者你設定嘅固定限制（以毫秒為單位）。 |

測試持續時間指標使用 Tuist 中記錄嘅測試運行。緩慢構建閾值僅適用於構建：當構建持續時間超過該閾值時，即視為緩慢。已取消嘅構建會單獨計算，並排除喺構建成功率之外。

### 緩存節省

| 指標 | 標識符 | 測量內容 |
| --- | --- | --- |
| 累計任務時間節省（Gradle） | `cache_work_avoided` | 由快取命中避免嘅估計任務執行時間總和。 |
| 報告累計任務時間嘅構建 | `cache_work_avoided_samples` | 具有完整估計值嘅構建。 |
| 報告嘅緩存節省時間 | `cache_time_saved` | 報告嘅經過時間節省總和。 |
| 報告緩存節省時間嘅構建 | `cache_time_saved_samples` | 具有有效節省值嘅構建。 |

Gradle 插件會自動報告本地同遠程任務快取命中所避免嘅估計工作量。對於每個快取任務，佢會從 Gradle 儲存嘅原始執行時間中減去任務嘅恢復持續時間，最小值為零。構建估計會將呢啲數值相加。並行任務可能會重疊，所以呢個係累計任務時間，而唔係節省嘅經過構建時間。最新同已跳過嘅任務會被排除。

如果構建沒有任務快取命中，則報告為零。如果任何快取任務缺少其原始計時、遙測數據不完整，或者自定義元數據映射沒有空間，插件就會省略該估計。較舊嘅插件版本同其他構建系統不會報告此數據。將報告數量同總構建數量進行比較以檢查覆蓋率。

報告嘅經過時間節省來自 `tuist.cache_time_saved_ms` 元數據。此指標與自動估計保持分離。

當沒有構建報告時，緩存節省沒有價值。Once 目前不會記錄此測量值。通過此數據源無法獲得快取命中率同未命中率。

### 表格

呢啲標識符係查詢嘅 `queryType` 字段嘅值。

| 表格 | 查詢類型 | 內容 |
| --- | --- | --- |
| 按工作負載劃分嘅健康狀況 | `buildWorkloads` | 構建數量、成功率、中位數同第 90 個百分位數持續時間。 |
| 失敗類別 | `buildFailureReasons` | 所有失敗同按失敗類別劃分嘅數量。 |
| 最近失敗嘅構建 | `buildRecentFailures` | 最新嘅 100 次失敗，帶有指向 Tuist 嘅鏈接。 |

最近嘅失敗包括開始時間、持續時間、用戶、分支同請求嘅任務。失敗類別為 `verification`、`infrastructure_tooling` 同 `unknown`。

工作負載摘要同分支/工作負載值列表最多返回 1000 個值。構建健康變量查詢使用過去 90 天；舊版 Gradle 變量查詢保留其現有嘅歷史窗口。Bazel 顯示由工具報告嘅構建用戶。其他集成顯示與報告憑證相關聯嘅帳戶。歷史 Bazel 同 Once 運行，以及使用項目憑證報告嘅 Once 運行，在沒有記錄用戶時顯示為未知。

使用構建運行上嘅失敗類別過濾器來查找匹配嘅失敗。該類別出現在構建詳情中，並帶有一個解釋其含義嘅信息提示；默認概覽同構建運行表格保留其現有列。成功、已取消同未完成嘅構建沒有失敗類別。Gradle 嘅緩存分析卡片同構建詳情顯示累計任務時間節省；工具提示解釋估計值同並行任務嘅影響。緩存小部件使用相同嘅過濾器將所選範圍與緊接之前嘅同等長度時期進行比較。比較係中立嘅：較大嘅總數可能反映更多構建。缺少先前估計值則不顯示比較；記錄嘅零基線顯示絕對增加而非百分比。

## 標準儀表板 {#what-you-can-query}

導入 [構建健康儀表板](https://github.com/tuist/tuist/blob/main/grafana-datasource/src/dashboards/build-health.json)，然後選擇你嘅數據源同項目。它包括構建數量、成功率、中位數同第 90 個百分位數持續時間、緩慢構建閾值、中立嘅失敗或緩慢構建數量、分組嘅緩存節省同報告覆蓋率，以及三個失敗同工作負載表格。根據需要添加其他可用指標嘅面板。自動緩慢閾值係所選時期自身嘅第 90 個百分位數；高於此值嘅構建不一定表示回歸。為持續時間目標警報設置固定閾值。緩存面板優先顯示 Gradle 嘅自動累計任務時間估計及其覆蓋率，然後係明確報告嘅經過時間節省及其自身嘅覆蓋率。

## 構建系統 {#build-systems}

構建健康查詢同標準儀表板支持 Bazel、Once、Gradle 同 Xcode。Tuist 從你嘅項目中選擇構建系統。混合項目目前不受構建健康查詢或標準儀表板支持。

| 構建系統 | 工作負載 | 取消報告 | 緩存節省 |
| --- | --- | --- | --- |
| Bazel | 命令 | 退出代碼 8，除了 `run` | 需要自定義元數據 |
| Once | 命令種類 | 記錄嘅取消原因 | 未記錄 |
| Gradle | 任務組 | 已報告嘅取消 | 自動工作避免估計；經過時間節省需要自定義元數據 |
| Xcode | 方案 | 未區分；計數為零 | 需要自定義元數據 |

處理中嘅記錄同未完成嘅運行被排除。Bazel 包括構建、測試、運行同覆蓋命令。Once 包括已完成嘅構建、測試同通用運行。

Gradle 將任務按優先順序分為儀器化測試、單元測試、lint/檢查、組裝/打包或其他。每個構建屬於一個工作負載。自定義元數據可以覆蓋 Xcode、Bazel 同 Gradle 嘅工作負載。

### 失敗類別

| 類別 | 含義 | 記錄嘅證據 |
| --- | --- | --- |
| `verification` | 代碼編譯、鏈接、測試或檢查失敗。 | Gradle 驗證或編譯異常及已知失敗任務類型；Xcode 編譯器同鏈接器問題；Bazel 結構化非零編譯器/測試操作結果；Once 測試失敗或明確聲明為編譯、鏈接、測試、lint 或檢查嘅失敗操作。 |
| `infrastructure_tooling` | 由於工具、依賴項或環境失敗，構建無法正常運行。 | Gradle 配置、依賴解析、輸入/輸出或內存失敗；Bazel 結構化基礎設施失敗同 [記錄嘅退出代碼](https://bazel.build/run/scripts)；Once 基礎設施操作錯誤。 |
| `unknown` | 報告中沒有足夠嘅證據來對失敗進行分類。 | 任意命令、缺少診斷信息，以及沒有結構化證據嘅舊報告。 |

Gradle 配置階段失敗（包括構建腳本中嘅錯誤）被歸類為基礎設施/工具，因為任務執行無法繼續。

顯式 `tuist.failure_category` 元數據會覆蓋自動分類。否則，當構建中同時出現基礎設施同驗證證據時，基礎設施證據優先。失敗嘅任意腳本不被假定為編譯器或測試失敗。歷史報告可以使用 Tuist 已經存儲嘅證據，但新嘅報告者字段不會回填缺失信息。自動報告者元數據使用現有 20 條自定義元數據限制內嘅可用空間。

`buildFailureReasons` 響應保留其 `all` 行以保持兼容性。標準儀表板從失敗類別圖表中過濾掉該總數，並單獨顯示總失敗數。傳統 `gradleFailureReasons` 查詢保留其原始三個類別行。

## 查詢選項 {#query-options}

數字查詢使用這些 `queryType` 值：

| 查詢 | 查詢類型 |
| --- | --- |
| 構建健康 | `buildHealth` |
| Xcode 構建持續時間 | `buildDuration` |
| 測試持續時間 | `testDuration` |

`resultMode` 字段控制結果如何返回：

| 結果 | 值 | 行為 |
| --- | --- | --- |
| 時間序列 | `series` | 每個間隔一個值。 |
| 整個時期 | `total` | 從範圍內所有運行計算得出的一個值。 |

過濾器標籤映射到這些查詢字段：

| 過濾器 | 查詢字段 | 適用於 |
| --- | --- | --- |
| 環境 | `environment` | 所有查詢 |
| 分支 | `gitBranch` | 構建健康查詢同表格 |
| 工作負載 | `workload` | 構建健康查詢同表格 |
| 狀態 | `status` | 構建健康查詢、表格同 Xcode 持續時間 |
| Scheme | `scheme` | Xcode 構建同測試持續時間 |
| 配置 | `configuration` | Xcode 構建持續時間 |
| 構建類型 | `category` | Xcode 構建持續時間 |

環境值為 `any`、`ci`（自動化構建）同 `local`。狀態值為 `success`、`failure`，而對於構建健康查詢則包括 `cancelled`；省略該值以包含所有狀態。構建類型值為 `clean` 同 `incremental`；省略該值以包含兩者。

空嘅構建健康間隔計數為零，且沒有平均持續時間、持續時間百分位數或成功率值。慢構建閾值仍然使用完整嘅所選範圍。獨立嘅測試持續時間查詢對空時間序列間隔返回零。整個時期嘅百分位數係根據運行計算，而非根據間隔百分位數計算。構建健康百分位數使用精確聚合；獨立嘅 Xcode 同測試持續時間查詢使用近似百分位數。

構建健康時間序列將部分第一個桶放置喺所選範圍嘅開始處，以保持其可見性。傳統 Gradle 查詢保留其原始桶時間戳。

所有查詢接受最多 366 天嘅日期範圍。佢哋嘅邊界同時間戳有所不同：

| 查詢 | 使用嘅時間戳 | 範圍邊界 |
| --- | --- | --- |
| 構建健康：Xcode、Bazel、Gradle | 記錄插入時間 | 包含開始，排除結束 |
| 構建健康：Once | 運行開始時間 | 包含開始，排除結束 |
| Xcode 構建持續時間 | 記錄插入時間 | 排除開始同結束 |
| 測試持續時間 | 記錄嘅運行時間 | 包含開始同結束 |

### 儀表板變量

對項目同受支持嘅過濾器使用儀表板變量。分支同工作負載變量使用以下查詢：

| 變量 | 查詢 |
| --- | --- |
| 分支 | `buildBranches account/project` |
| 工作負載 | `buildWorkloads account/project` |

過濾器只接受一個精確值。對於分支同工作負載變量，將「全部」選項嘅自定義值設為 `__tuist_all__`。其他過濾器使用其內置嘅「任何」選項或空值。不支持多選同正則表達式。

## 報告自定義元數據 {#custom-metadata}

Xcode、Bazel 同 Gradle 構建接受以下可選元數據值：

| 鍵 | 接受嘅值 |
| --- | --- |
| `tuist.workload` | 取代默認分組嘅工作負載名稱。 |
| `tuist.failure_category` | `verification` 或 `infrastructure_tooling`。 |
| `tuist.cache_work_avoided_ms` | 僅限 Gradle。自動報告嘅避免工作量估算，以整數毫秒為單位，最多 365 天。 |
| `tuist.cache_time_saved_ms` | 從 0 到 31,536,000,000（365 天）嘅整數毫秒。 |

通過你嘅構建集成嘅自定義元數據配置提供佢哋：

```json
{
  "custom_metadata": {
    "values": {
      "tuist.workload": "Release verification",
      "tuist.failure_category": "verification",
      "tuist.cache_time_saved_ms": "12000"
    }
  }
}
```

僅當你對該構建有經過時間測量或文檔化嘅估算時，才報告緩存節省。當任務並行運行時，僅靠緩存命中同累積任務持續時間無法確定經過嘅節省。缺失嘅緩存節省仍然未知。缺失嘅失敗類別元數據會回退到記錄嘅證據，如 [構建系統](#build-systems) 中所述。數據保留不變。

## 警報同 Slack {#alerts-and-slack}

使用數值指標創建由 Grafana 管理嘅警報規則。例如：

| 指標 | 標識符 | 示例條件 |
| --- | --- | --- |
| 構建成功率 | `success_rate` | 低於 99% |
| 失敗嘅構建 | `failed_builds` | 高於零 |
| 第 90 百分位持續時間 | `p90` | 高於你團隊嘅持續時間限制 |

使用 **整個時期** 獲取評估窗口內嘅單一值，或將時間序列縮減為單一值。對於「整個時期」模式下嘅持續時間查詢，選擇一個序列。

- 使用固定嘅項目同過濾器值。後台警報評估期間無法使用儀表板變量。
- 對警報使用數值查詢。要監控工作負載，請將構建健康查詢過濾到該工作負載。
- 為沒有構建或報告緩存節省嘅間隔設置規則嘅無數據行為。

配置 [Slack 聯繫點](https://grafana.com/docs/grafana/latest/alerting/configure-notifications/manage-contact-points/integrations/configure-slack/) 並通過 Grafana 嘅通知策略將規則路由到佢。Grafana 發送通知並存儲 Slack 憑據。

## 升級現有儀表板 {#upgrading}

現有嘅持續時間面板保留其查詢、過濾器、序列名稱同單位。已保存嘅 Gradle 健康面板同變量也繼續有效。

單獨導入標準儀表板以使用共享嘅構建健康查詢。現有儀表板不會自動遷移。共享查詢需要提供支持構建健康端點嘅 Tuist 服務器；現有嘅持續時間查詢仍可在較舊嘅服務器上工作。

## 要求 {#requirements}

- Grafana 10.4 或更高版本。
- 具有讀取你想要繪製圖表嘅項目同指標權限嘅 Tuist 令牌。請參閱下面嘅 [身份驗證](#authentication)。

## 身份驗證 {#authentication}

使用 <.localized_link href="/guides/server/authentication#account-tokens">帳戶令牌</.localized_link> 進行儀表板同後台警報評估。授予 `project:builds:read` 以獲取構建指標，授予 `project:tests:read` 以獲取測試持續時間，並限制對你想要繪製圖表嘅項目嘅訪問。只需要你使用嘅指標所對應嘅範圍。按照 <.localized_link href="/guides/server/authentication#creating-an-account-token">令牌創建說明</.localized_link> 生成一個。

集成還接受現有項目令牌用於其自身項目，以及具有用戶讀取權限嘅 <.localized_link href="/guides/server/authentication#as-a-user">用戶訪問令牌</.localized_link>。用戶訪問令牌係短期有效嘅。Grafana 存儲你提供嘅令牌，不會刷新佢或重用你本地嘅 Tuist 登錄；當佢過期時請更換佢。帳戶令牌讓你可以獨立於用戶嘅登錄會話來控制項目訪問、權限同過期時間。

## 配置 {#configuration}

添加數據源並設置：

| 欄位 | 已儲存設定 | 備註 |
| --- | --- | --- |
| 伺服器 URL | `jsonData.url` | 預設為 `https://tuist.dev`。 |
| 令牌 | `secureJsonData.apiToken` | Tuist bearer token，加密儲存。 |

選擇 **Save & test** 以檢查連線。Grafana 會列出可存取嘅項目，然後針對第一個項目檢查構建同測試嘅讀取權限。

## 安裝 {#installation}

### 從 Grafana 目錄 {#from-the-grafana-catalog}

發佈後，可以好似其他數據源一樣，透過 **Connections → Add new connection → Tuist** 安裝，或者使用 `grafana-cli plugins install tuist-metrics-datasource` 安裝。

### 發佈之前（自託管 Grafana）{#before-it-is-published-self-hosted-grafana}

插件在獲准加入目錄之前係未簽署嘅。喺自託管實例上，你可以：

- **允許未簽署** — 將 `tuist-metrics-datasource` 加入 `allow_loading_unsigned_plugins`（或 `GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=tuist-metrics-datasource`），然後將構建好嘅插件放入你嘅插件目錄。
- 為你嘅實例 **私下簽署** — `npm run sign -- --rootUrls https://grafana.example.com`（URL 必須同實例 `root_url` 匹配），然後分發 zip 檔案。

[Grafana Cloud 要求使用目錄中嘅插件](https://grafana.com/docs/grafana-cloud/learn-and-build/get-started/learn/find-and-use-plugins/)，唔支援未簽署或手動上傳嘅插件。
