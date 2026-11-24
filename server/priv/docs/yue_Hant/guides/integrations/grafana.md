---
{
  "title": "Grafana",
  "titleTemplate": ":title | 整合 | 指南 | Tuist",
  "description": "在 Grafana 中監控 Tuist 的建置健康狀況、持續時間和快取節省情況，並為你的團隊設定警報。"
}
---

# Grafana 整合 {#grafana}

Tuist 數據源讓你在 Grafana 中使用構建、測試和快取指標，包括持續時間、失敗次數，以及快取所節省的時間。圍繞你的團隊關注的項目和指標構建儀表板，或將 Tuist 指標與公司現有儀表板中的其他數據源結合。使用 Grafana 的警報規則和通知渠道，讓你的團隊在構建變慢或失敗增加時收到通知。

## 可用指標 {#metric-definitions}

表格列出了可讀標籤及其查詢標識符。構建健康查詢使用 `metric` 字段中的標識符；構建和測試持續時間查詢在 `series` 字段中選擇 `average`、`p50`、`p90` 或 `p99`。

### 構建次數和可靠性

| 指標 | 標識符 | 測量內容 |
| --- | --- | --- |
| 構建次數 | `builds` | 記錄的構建數量。 |
| 成功構建 | `successful_builds` | 成功完成的構建。 |
| 失敗構建 | `failed_builds` | 失敗的構建。 |
| 已取消構建 | `cancelled_builds` | 記錄為已取消的構建。參見 [構建系統差異](#build-systems)。 |
| 構建成功率 | `success_rate` | 成功 ÷ (成功 + 失敗)，以百分比表示。 |
| 失敗或緩慢構建 | `builds_needing_attention` | 失敗或緩慢的構建，每個構建只計算一次。 |

### 構建和測試持續時間

| 指標 | 標識符 | 測量內容 |
| --- | --- | --- |
| 平均持續時間 | `average` | 所選運行的平均持續時間。 |
| 中位數持續時間 | `p50` | 運行持續時間的第 50 個百分位數。 |
| 第 90 個百分位數持續時間 | `p90` | 90% 的運行低於或等於此持續時間。 |
| 第 99 個百分位數持續時間 | `p99` | 99% 的運行低於或等於此持續時間。 |
| 緩慢構建閾值 | `slow_build_threshold` | 第 90 個百分位數持續時間，或你設定的毫秒固定限制。 |

測試持續時間指標使用 Tuist 中記錄的測試運行。緩慢構建閾值僅適用於構建：當構建持續時間超過該閾值時，即視為緩慢。已取消的構建會單獨計算，並從構建成功率中排除。

### 快取節省

| 指標 | 標識符 | 測量內容 |
| --- | --- | --- |
| 累計任務時間節省 (Gradle) | `cache_work_avoided` | 快取命中所避免的估計任務執行時間總和。 |
| 報告累計任務時間的構建 | `cache_work_avoided_samples` | 具有完整估算的構建。 |
| 報告的快取節省時間 | `cache_time_saved` | 報告的經過時間節省總和。 |
| 報告快取節省時間的構建 | `cache_time_saved_samples` | 具有有效節省值的構建。 |

Gradle 外掛程式會自動報告本機和遠端任務快取命中所避免的估計工作量。對於每個快取任務，它會從 Gradle 儲存的原始執行時間中減去任務的恢復持續時間，最小值為零。構建估算會將這些值相加。平行任務可能會重疊，因此這是累計任務時間，而非節省的經過構建時間。最新和跳過的任務不包括在內。

沒有任務快取命中的構建會報告零。如果任何快取任務缺少其原始計時、遙測數據不完整，或自訂元資料映射沒有空間，外掛程式會省略估算。較舊的外掛程式版本和其他構建系統不會報告此數據。將報告數量與總構建數進行比較以檢查覆蓋率。

報告的經過時間節省來自 `tuist.cache_time_saved_ms` 元資料。此指標與自動估算保持分開。

當沒有構建報告快取節省時，該值為空。Once 目前未記錄此測量數據。此數據源不提供快取命中率和未命中率。

### 表格

這些標識符是查詢的 `queryType` 字段的值。

| 表格 | 查詢類型 | 內容 |
| --- | --- | --- |
| 按工作負載的健康狀況 | `buildWorkloads` | 構建次數、成功率、中位數和第 90 個百分位數持續時間。 |
| 失敗類別 | `buildFailureReasons` | 所有失敗及其按失敗類別的數量。 |
| 最近的失敗構建 | `buildRecentFailures` | 最新的 100 次失敗，並附有指向 Tuist 的連結。 |

最近的失敗包括開始時間、持續時間、用戶、分支和請求的任務。失敗類別為 `verification`、`infrastructure_tooling` 和 `unknown`。

工作負載摘要和分支/工作負載值列表最多返回 1000 個值。構建健康變量查詢使用過去 90 天的數據；舊版 Gradle 變量查詢保留其現有的歷史窗口。Bazel 顯示工具報告的構建用戶。其他整合顯示與報告憑證關聯的帳戶。當沒有記錄用戶時，歷史 Bazel 和 Once 運行，以及使用項目憑證報告的 Once 運行，會顯示為未知。

在「構建運行」上使用「失敗類別」過濾器來查找匹配的失敗。該類別出現在構建詳情中，並附有解釋其含義的信息提示；默認概覽和「構建運行」表格保留其現有列。成功、已取消和未完成的構建沒有失敗類別。Gradle 的「快取分析」卡片和構建詳情顯示「累計任務時間節省」；工具提示解釋了估算和平行任務的影響。快取小部件使用相同的過濾器，將所選範圍與緊接之前的同等長度時期進行比較。比較是中性的：較大的總數可能反映更多的構建。缺少之前的估算則不顯示比較；記錄的零基準顯示絕對增加而非百分比。

## 標準儀表板 {#what-you-can-query}

導入 [構建健康儀表板](https://github.com/tuist/tuist/blob/main/grafana-datasource/src/dashboards/build-health.json)，然後選擇你的數據源和項目。它包括構建次數、成功率、中位數和第 90 個百分位數持續時間、緩慢構建閾值、中性的失敗或緩慢構建計數、分組的快取節省和報告覆蓋率，以及三個失敗和工作負載表格。根據需要添加其他可用指標的面板。自動緩慢閾值是所選時期自身的第 90 個百分位數；高於此閾值的構建不一定表示回歸。為持續時間目標警報設定固定閾值。快取面板優先顯示 Gradle 的自動累計任務時間估算及其覆蓋率，其次是明確報告的經過時間節省及其覆蓋率。

## 構建系統 {#build-systems}

構建健康查詢和標準儀表板支持 Bazel、Cargo、Once、Gradle 和 Xcode。Tuist 從你的項目中選擇構建系統。混合項目目前不受構建健康查詢或標準儀表板支持。

| 構建系統 | 工作負載 | 取消報告 | 快取節省 |
| --- | --- | --- | --- |
| Bazel | 命令 | 退出代碼 8，除了 `run` | 需要自訂元資料 |
| Cargo | 命令 | 未區分；計數為零 | 經過時間節省需要自訂元資料；避免的編譯器工作不屬於經過時間節省 |
| Once | 命令類型 | 已記錄的取消原因 | 未記錄 |
| Gradle | 任務組 | 已報告的取消 | 自動避免工作估算；經過時間節省需要自訂元資料 |
| Xcode | 方案 | 未區分；計數為零 | 需要自訂元資料 |

處理中的記錄和未完成的運行會被排除。Bazel 包括構建、測試、運行和覆蓋率命令。Once 包括已最終確定的構建、測試和通用運行。Cargo 包括如 `build`、`check` 和 `test-build` 等構建命令；舊版測試執行報告不包括在構建健康中。Cargo 最近的失敗在可用時使用記錄的開始時間，否則回退到插入時間；缺少的持續時間保持不可用而非設為零。

Gradle 按優先順序將任務分為儀器化測試、單元測試、lint/檢查、組裝/打包或其他。每個構建屬於一個工作負載。自訂元資料可以覆蓋 Xcode、Bazel、Cargo 和 Gradle 的工作負載。

### 失敗類別

| 類別 | 含義 | 已記錄的證據 |
| --- | --- | --- |
| `verification` | 代碼編譯、鏈接、測試或檢查失敗。 | Gradle 驗證或編譯異常及已知失敗的任務類型；Xcode 編譯器和鏈接器問題；Bazel 結構化的非零編譯器/測試操作結果；Cargo 記錄的失敗 rustc 編譯；Once 測試失敗或明確聲明為編譯、鏈接、測試、lint 或檢查的失敗操作。 |
| `infrastructure_tooling` | 由於工具、依賴項或環境失敗，構建無法正常運行。 | Gradle 配置、依賴解析、輸入/輸出或內存失敗；Bazel 結構化的基礎設施失敗和 [記錄的退出代碼](https://bazel.build/run/scripts)；Once 基礎設施操作錯誤。 |
| `unknown` | 報告沒有足夠的證據來分類失敗。 | 任意命令、缺少診斷信息，以及沒有結構化證據的舊報告。 |

Gradle 配置階段的失敗，包括構建腳本中的錯誤，被歸類為基礎設施/工具，因為任務執行無法繼續。

沒有明確類別元資料或記錄的失敗 rustc 編譯的 Cargo 失敗仍保持為 `unknown`；單獨失敗的 `check` 或 `test-build` 命令不足以確立驗證失敗。Cargo 任務重用計數器和估算的避免編譯器工作從不提供經過時間快取節省或 Gradle 的累計任務時間指標。

明確的 `tuist.failure_category` 元資料會覆蓋自動分類。否則，當構建中同時出現基礎設施和驗證證據時，基礎設施證據優先。失敗的任意腳本不被假定為編譯器或測試失敗。歷史報告可以使用 Tuist 已存儲的證據，但新的報告者字段不會回填缺失的信息。自動報告者元資料使用現有 20 條自訂元資料限制內的可用空間。

`buildFailureReasons` 響應保留其 `all` 行以確保兼容性。標準儀表板從失敗類別圖表中過濾掉該總數，並單獨顯示總失敗數。舊版 `gradleFailureReasons` 查詢保留其原始的三個類別行。

## 查詢選項 {#query-options}

數值查詢使用這些 `queryType` 值：

| 查詢 | 查詢類型 |
| --- | --- |
| 構建健康 | `buildHealth` |
| Xcode 構建持續時間 | `buildDuration` |
| 測試持續時間 | `testDuration` |

`resultMode` 字段控制結果的返回方式：

| 結果 | 值 | 行為 |
| --- | --- | --- |
| 時間序列 | `series` | 每個間隔一個值。 |
| 整個期間 | `total` | 根據範圍內所有運行計算的一個值。 |

篩選標籤對應以下查詢字段：

| 篩選條件 | 查詢字段 | 適用於 |
| --- | --- | --- |
| 環境 | `environment` | 所有查詢 |
| 分支 | `gitBranch` | 構建健康查詢和表格 |
| 工作負載 | `workload` | 構建健康查詢和表格 |
| 狀態 | `status` | 構建健康查詢、表格和 Xcode 持續時間 |
| Scheme | `scheme` | Xcode 構建和測試持續時間 |
| Configuration | `configuration` | Xcode 構建持續時間 |
| 構建類型 | `category` | Xcode 構建持續時間 |

環境值為 `any`、`ci`（自動構建）和 `local`。狀態值為 `success`、`failure`，以及針對構建健康查詢的 `cancelled`；省略該值以包含所有狀態。構建類型值為 `clean` 和 `incremental`；省略該值以同時包含兩者。

空的構建健康間隔計數為零，且沒有平均持續時間、持續時間百分位數或成功率值。慢構建閾值仍使用所選的完整範圍。獨立的測試持續時間查詢對空時間序列間隔返回零。整個期間的百分位數是根據運行計算的，而不是根據間隔百分位數。構建健康百分位數使用精確聚合；獨立的 Xcode 和測試持續時間查詢使用近似百分位數。

構建健康時間序列在所選範圍的開始處放置一個部分的第一個桶，以保持其可見性。舊版 Gradle 查詢保留其原始的桶時間戳。

所有查詢接受最長 366 天的日期範圍。它們的邊界和時間戳有所不同：

| 查詢 | 使用的時間戳 | 範圍邊界 |
| --- | --- | --- |
| 構建健康：Xcode、Bazel、Cargo、Gradle | 記錄插入時間 | 包含開始，排除結束 |
| 構建健康：Once | 運行開始時間 | 包含開始，排除結束 |
| Xcode 構建持續時間 | 記錄插入時間 | 排除開始和結束 |
| 測試持續時間 | 記錄的運行時間 | 包含開始和結束 |

### 儀表板變數

為專案和支援的篩選條件使用儀表板變數。分支和工作負載變數使用以下查詢：

| 變數 | 查詢 |
| --- | --- |
| 分支 | `buildBranches account/project` |
| 工作負載 | `buildWorkloads account/project` |

篩選條件接受一個精確值。對於分支和工作負載變數，將「全部」選項的自訂值設為 `__tuist_all__`。其他篩選條件使用其內建的「任何」選項或空值。不支援多選和正規表示式。

## 報告自訂中繼資料 {#custom-metadata}

Xcode、Bazel、Cargo 和 Gradle 構建接受這些可選的中繼資料值：

| 鍵 | 接受的值 |
| --- | --- |
| `tuist.workload` | 取代預設分組的工作負載名稱。 |
| `tuist.failure_category` | `verification` 或 `infrastructure_tooling`。 |
| `tuist.cache_work_avoided_ms` | 僅限 Gradle。自動報告的避免工作量估計值，以整數毫秒為單位，最長 365 天。 |
| `tuist.cache_time_saved_ms` | 從 0 到 31,536,000,000（365 天）的整數毫秒。 |

透過您的構建整合的自訂中繼資料設定提供它們：

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

僅當您有該構建的經過時間測量值或記錄在案的估計值時，才報告快取節省量。當任務並行運行時，僅靠快取命中和累積任務持續時間無法確定經過的節省量。缺少的快取節省量仍為未知。缺少的失敗類別中繼資料會回退到記錄的證據，如 [構建系統](#build-systems) 下所述。資料保留不變。

## 警報和 Slack {#alerts-and-slack}

建立具有數值指標的 Grafana 管理警報規則。例如：

| 指標 | 識別碼 | 範例條件 |
| --- | --- | --- |
| 構建成功率 | `success_rate` | 低於 99% |
| 失敗的構建 | `failed_builds` | 高於零 |
| 第 90 百分位數持續時間 | `p90` | 高於您團隊的持續時間限制 |

使用 **整個期間** 來獲取評估視窗內的單一值，或將時間序列縮減為單一值。對於「整個期間」模式的持續時間查詢，請選擇一個序列。

- 使用固定的專案和篩選條件值。在背景警報評估期間，儀表板變數不可用。
- 對警報使用數值查詢。若要監控工作負載，請將構建健康查詢篩選至該工作負載。
- 為沒有構建或報告快取節省量的間隔設定規則的無資料行為。

設定 [Slack 聯絡點](https://grafana.com/docs/grafana/latest/alerting/configure-notifications/manage-contact-points/integrations/configure-slack/)，並透過 Grafana 的通知政策將規則路由至該聯絡點。Grafana 發送通知並儲存 Slack 憑證。

## 升級現有儀表板 {#upgrading}

現有的持續時間面板保留其查詢、篩選條件、序列名稱和單位。已儲存的 Gradle 健康面板和變數也繼續有效。

單獨匯入標準儀表板以使用共用的構建健康查詢。現有儀表板不會自動遷移。共用查詢需要提供構建健康端點的 Tuist 伺服器；現有持續時間查詢仍可在較舊的伺服器上運作。

## 需求 {#requirements}

- Grafana 10.4 或更新版本。
- 具有讀取您要繪製圖表的專案和指標權限的 Tuist 令牌。請參閱下方的 [驗證](#authentication)。

## 驗證 {#authentication}

儀表板和背景警報評估使用 <.localized_link href="/guides/server/authentication#account-tokens">帳戶令牌</.localized_link>。授予 `project:builds:read` 以取得構建指標，以及 `project:tests:read` 以取得測試持續時間，並限制對您要繪製圖表的專案的存取權限。僅需要您使用的指標範圍。請依照 <.localized_link href="/guides/server/authentication#creating-an-account-token">令牌建立說明</.localized_link> 產生一個。

整合也接受現有專案令牌（用於其自身專案）和具有使用者讀取權限的 <.localized_link href="/guides/server/authentication#as-a-user">使用者存取令牌</.localized_link>。使用者存取令牌有效期較短。Grafana 會儲存您提供的令牌，但不會重新整理或重複使用您的本機 Tuist 登入；請在過期時更換。帳戶令牌讓您能夠獨立於使用者的登入工作階段來控制專案存取權限、權限和到期時間。

## 設定 {#configuration}

新增資料來源並設定：

| 欄位 | 已儲存的設定 | 備註 |
| --- | --- | --- |
| 伺服器 URL | `jsonData.url` | 預設為 `https://tuist.dev`。 |
| 令牌 | `secureJsonData.apiToken` | Tuist bearer 令牌，加密儲存。 |

選擇 **儲存並測試** 以檢查連線。Grafana 會列出可存取的專案，然後針對第一個專案檢查構建和測試的讀取權限。

## 安裝 {#installation}

### 從 Grafana 目錄 {#from-the-grafana-catalog}

發布後，像其他資料來源一樣從 **Connections → Add new connection → Tuist** 安裝，或使用 `grafana-cli plugins install tuist-metrics-datasource`。

### 在發布之前（自託管 Grafana）{#before-it-is-published-self-hosted-grafana}

外掛程式在獲得目錄核准之前是未簽名的。在自託管實例上，您可以：

- **允許未签名** — 將 `tuist-metrics-datasource` 加入 `allow_loading_unsigned_plugins`（或 `GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=tuist-metrics-datasource`），並將構建的外掛程式放入您的外掛程式目錄。
- 為您的實例**私下簽名** — `npm run sign -- --rootUrls https://grafana.example.com`（URL 必須與實例 `root_url` 相符），然後分發 zip 檔案。

[Grafana Cloud 要求使用目錄中的外掛程式](https://grafana.com/docs/grafana-cloud/learn-and-build/get-started/learn/find-and-use-plugins/)，且不支援未签名或手動上傳的外掛程式。
