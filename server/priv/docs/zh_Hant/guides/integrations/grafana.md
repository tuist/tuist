---
{
  "title": "Grafana",
  "titleTemplate": ":title | 整合 | 指南 | Tuist",
  "description": "在 Grafana 中監控 Tuist 建置健康狀態、持續時間與快取節省成效，並為你的團隊設定警示。"
}
---

# Grafana 整合 {#grafana}

Tuist 資料來源可讓你在 Grafana 中使用建置、測試與快取指標，包括持續時間、失敗次數，以及快取所節省的時間。圍繞團隊關注的專案與指標打造儀表板，或將 Tuist 指標與公司既有儀表板中的其他資料來源結合。使用 Grafana 的警示規則與通知管道，在建置變慢或失敗增加時通知團隊。

## 可用指標 {#metric-definitions}

表格列出可讀標籤及其查詢識別碼。建置健康度查詢使用 `metric` 欄位中的識別碼；建置與測試持續時間查詢則在 `series` 欄位中選擇 `average`、`p50`、`p90` 或 `p99`。

### 建置數量與可靠性

| 指標 | 識別碼 | 測量內容 |
| --- | --- | --- |
| 建置數量 | `builds` | 已記錄的建置數量。 |
| 成功建置 | `successful_builds` | 成功完成的建置。 |
| 失敗建置 | `failed_builds` | 失敗的建置。 |
| 已取消建置 | `cancelled_builds` | 記錄為已取消的建置。請參閱[建置系統差異](#build-systems)。 |
| 建置成功率 | `success_rate` | 成功 ÷（成功 + 失敗），以百分比表示。 |
| 失敗或緩慢的建置 | `builds_needing_attention` | 失敗或緩慢的建置，每個建置僅計一次。 |

### 建置與測試持續時間

| 指標 | 識別碼 | 測量內容 |
| --- | --- | --- |
| 平均持續時間 | `average` | 所選執行次數的平均持續時間。 |
| 中位數持續時間 | `p50` | 執行持續時間的第 50 百分位數。 |
| 第 90 百分位數持續時間 | `p90` | 90% 的執行落在該持續時間或以下。 |
| 第 99 百分位數持續時間 | `p99` | 99% 的執行落在該持續時間或以下。 |
| 緩慢建置閾值 | `slow_build_threshold` | 第 90 百分位數持續時間，或你設定的固定毫秒上限。 |

測試持續時間指標使用 Tuist 中記錄的測試執行。緩慢建置閾值僅適用於建置：當建置持續時間超過該閾值時，即視為緩慢。已取消的建置會單獨計算，並從建置成功率中排除。

### 快取節省

| 指標 | 識別碼 | 測量內容 |
| --- | --- | --- |
| 累計任務時間節省（Gradle） | `cache_work_avoided` | 快取命中所避免的預估任務執行時間總和。 |
| 回報累計任務時間的建置 | `cache_work_avoided_samples` | 具有完整預估值的建置。 |
| 回報的快取節省時間 | `cache_time_saved` | 回報的經過時間節省總和。 |
| 回報快取節省時間的建置 | `cache_time_saved_samples` | 具有有效節省值的建置。 |

Gradle 外掛程式會自動回報本機與遠端任務快取命中所避免的預估工作量。針對每個快取任務，它會從 Gradle 儲存的原始執行時間中減去任務的還原持續時間，最小值為零。建置預估值會將這些數值加總。平行任務可能會重疊，因此這是累計任務時間，而非節省的經過建置時間。已更新與跳過的任務則排除在外。

沒有任務快取命中的建置會回報零。如果任何快取任務缺少其原始計時、遙測資料不完整，或自訂中繼資料映射沒有空間，外掛程式就會省略該預估值。較舊的外掛程式版本與其他建置系統不會回報此資料。請將回報數量與總建置數量進行比較，以檢查涵蓋範圍。

回報的經過時間節省來自 `tuist.cache_time_saved_ms` 中繼資料。此指標與自動預估值保持獨立。

當沒有建置回報時，快取節省沒有數值。Once 目前不會記錄此測量結果。此資料來源不提供快取命中率與未命中率。

### 表格

這些識別碼是查詢的 `queryType` 欄位值。

| 表格 | 查詢類型 | 內容 |
| --- | --- | --- |
| 依工作負載的健康度 | `buildWorkloads` | 建置數量、成功率、中位數與第 90 百分位數持續時間。 |
| 失敗類別 | `buildFailureReasons` | 所有失敗及其按失敗類別分類的數量。 |
| 近期失敗建置 | `buildRecentFailures` | 最新 100 次失敗，並附有 Tuist 連結。 |

近期失敗包含開始時間、持續時間、使用者、分支與請求的任務。失敗類別為 `verification`、`infrastructure_tooling` 與 `unknown`。

工作負載摘要與分支/工作負載值清單最多傳回 1000 個值。建置健康度變數查詢使用過去 90 天；舊版 Gradle 變數查詢則保留其現有的歷史區間。Bazel 顯示工具回報的建置使用者。其他整合則顯示與回報憑證關聯的帳戶。當未記錄使用者時，歷史 Bazel 與 Once 執行，以及使用專案憑證回報的 Once 執行，會顯示為「未知」。

在建置執行上使用「失敗類別」篩選器以尋找相符的失敗。該類別會出現在建置詳細資訊中，並附有說明其含義的資訊提示；預設概覽與建置執行表格則保留其現有欄位。成功、已取消與未完成的建置沒有失敗類別。Gradle 的快取分析卡片與建置詳細資訊會顯示「累計任務時間節省」；工具提示會解釋預估值與平行任務的影響。快取小工具會使用相同的篩選器，將所選範圍與緊接在前的等長期間進行比較。比較結果是中性的：較大的總數可能反映更多的建置。缺少先前的預估值時不會顯示比較；記錄為零的基準線會顯示絕對增加量，而非百分比。

## 標準儀表板 {#what-you-can-query}

匯入[建置健康度儀表板](https://github.com/tuist/tuist/blob/main/grafana-datasource/src/dashboards/build-health.json)，然後選擇你的資料來源與專案。它包含建置數量、成功率、中位數與第 90 百分位數持續時間、緩慢建置閾值、中性的失敗或緩慢建置數量、分組的快取節省與回報涵蓋範圍，以及三個失敗與工作負載表格。視需要新增其他可用指標的面板。自動緩慢閾值是所選期間本身的第 90 百分位數；高於該閾值的建置不一定表示回歸。請設定固定閾值以用於持續時間目標警示。快取面板優先顯示 Gradle 的自動累計任務時間預估值及其涵蓋範圍，接著顯示明確回報的經過時間節省及其涵蓋範圍。

## 建置系統 {#build-systems}

建置健康度查詢與標準儀表板支援 Bazel、Once、Gradle 與 Xcode。Tuist 會從你的專案中選擇建置系統。混合專案目前不受建置健康度查詢或標準儀表板支援。

| 建置系統 | 工作負載 | 取消回報 | 快取節省 |
| --- | --- | --- | --- |
| Bazel | 指令 | 退出碼 8，但 `run` 除外 | 需要自訂中繼資料 |
| Once | 指令種類 | 記錄的取消原因 | 未記錄 |
| Gradle | 任務群組 | 已回報的取消 | 自動工作避免預估值；經過時間節省需要自訂中繼資料 |
| Xcode | 方案 | 未區分；數量為零 | 需要自訂中繼資料 |

處理中的記錄與未完成的執行會被排除。Bazel 包含建置、測試、執行與涵蓋範圍指令。Once 包含已最終確定的建置、測試與一般執行。

Gradle 會依優先順序將任務分組為儀器化測試、單元測試、lint/檢查、組建/封裝或其他。每個建置屬於一個工作負載。自訂中繼資料可以覆寫 Xcode、Bazel 與 Gradle 的工作負載。

### 失敗類別

| 類別 | 含義 | 記錄的證據 |
| --- | --- | --- |
| `verification` | 程式碼在編譯、連結、測試或檢查時失敗。 | Gradle 驗證或編譯例外狀況與已知失敗的任務類型；Xcode 編譯器與連結器問題；Bazel 結構化的非零編譯器/測試動作結果；Once 測試失敗或明確宣告為編譯、連結、測試、lint 或檢查的失敗動作。 |
| `infrastructure_tooling` | 由於工具、相依性或環境失敗，建置無法正常執行。 | Gradle 設定、相依性解析、輸入/輸出或記憶體失敗；Bazel 結構化的基礎設施失敗與[文件記載的退出碼](https://bazel.build/run/scripts)；Once 基礎設施動作錯誤。 |
| `unknown` | 回報中沒有足夠的證據來分類失敗。 | 任意指令、缺少診斷資訊，以及沒有結構化證據的舊版回報。 |

Gradle 設定階段的失敗（包括建置腳本中的錯誤）被歸類於基礎設施/工具之下，因為任務執行無法繼續。

明確的 `tuist.failure_category` 中繼資料會覆寫自動分類。否則，當建置中同時出現基礎設施與驗證證據時，基礎設施證據優先。失敗的任意腳本不會被視為編譯器或測試失敗。歷史回報可以使用 Tuist 已儲存的證據，但新的回報欄位不會回填缺少的資訊。自動回報中繼資料會使用現有 20 筆自訂中繼資料限制內的可用空間。

`buildFailureReasons` 回應保留其 `all` 列以維持相容性。標準儀表板會從失敗類別圖表中篩選掉該總計，並單獨顯示總失敗數。舊版的 `gradleFailureReasons` 查詢保留其原始的三個類別列。

## 查詢選項 {#query-options}

數值查詢使用這些 `queryType` 值：

| 查詢 | 查詢類型 |
| --- | --- |
| 建置健康度 | `buildHealth` |
| Xcode 建置持續時間 | `buildDuration` |
| 測試持續時間 | `testDuration` |

`resultMode` 欄位控制結果的回傳方式：

| 結果 | 值 | 行為 |
| --- | --- | --- |
| 時間序列 | `series` | 每個間隔一個值。 |
| 整個期間 | `total` | 根據範圍內所有執行計算的一個值。 |

篩選標籤對應至這些查詢欄位：

| 篩選 | 查詢欄位 | 適用於 |
| --- | --- | --- |
| 環境 | `environment` | 所有查詢 |
| 分支 | `gitBranch` | 建置健康度查詢與表格 |
| 工作負載 | `workload` | 建置健康度查詢與表格 |
| 狀態 | `status` | 建置健康度查詢、表格與 Xcode 持續時間 |
| Scheme | `scheme` | Xcode 建置與測試持續時間 |
| 組態 | `configuration` | Xcode 建置持續時間 |
| 建置類型 | `category` | Xcode 建置持續時間 |

環境值為 `any`、`ci`（自動化建置）與 `local`。狀態值為 `success`、`failure`，以及在建置健康度查詢中的 `cancelled`；省略該值以包含所有狀態。建置類型值為 `clean` 與 `incremental`；省略該值以同時包含兩者。

空的建置健康度間隔計數為零，且沒有平均持續時間、持續時間百分位數或成功率值。慢速建置門檻仍使用完整的選定範圍。獨立的測試持續時間查詢會為空的時間序列間隔回傳零。整個期間的百分位數是根據執行計算，而非根據間隔百分位數。建置健康度百分位數使用精確聚合；獨立的 Xcode 與測試持續時間查詢使用近似百分位數。

建置健康度時間序列會在選定範圍的起始處放置一個部分的第一個桶，使其保持可見。舊版 Gradle 查詢保留其原始的桶時間戳記。

所有查詢接受最長 366 天的日期範圍。它們的邊界與時間戳記有所不同：

| 查詢 | 使用的時間戳記 | 範圍邊界 |
| --- | --- | --- |
| 建置健康度：Xcode、Bazel、Gradle | 記錄插入時間 | 包含起始，排除結束 |
| 建置健康度：Once | 執行開始時間 | 包含起始，排除結束 |
| Xcode 建置持續時間 | 記錄插入時間 | 排除起始與結束 |
| 測試持續時間 | 記錄的執行時間 | 包含起始與結束 |

### 儀表板變數

對專案與支援的篩選使用儀表板變數。分支與工作負載變數使用這些查詢：

| 變數 | 查詢 |
| --- | --- |
| 分支 | `buildBranches account/project` |
| 工作負載 | `buildWorkloads account/project` |

篩選器僅接受一個精確值。對於分支與工作負載變數，請將「全部」選項的自訂值設為 `__tuist_all__`。其他篩選器使用其內建的「任意」選項或空值。不支援多選與正規表示式。

## 回報自訂中繼資料 {#custom-metadata}

Xcode、Bazel 與 Gradle 建置接受這些選擇性的中繼資料值：

| 鍵 | 接受的值 |
| --- | --- |
| `tuist.workload` | 取代預設分組的工作負載名稱。 |
| `tuist.failure_category` | `verification` 或 `infrastructure_tooling`。 |
| `tuist.cache_work_avoided_ms` | 僅限 Gradle。自動回報的避免工作量估算值，以整數毫秒為單位，最長可達 365 天。 |
| `tuist.cache_time_saved_ms` | 介於 0 到 31,536,000,000（365 天）之間的整數毫秒。 |

透過你的建置整合自訂中繼資料設定提供這些值：

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

僅在你能測量該建置的經過時間或擁有文件化的估算值時，才回報快取節省量。當任務並行執行時，僅憑快取命中與累計任務持續時間無法決定經過時間的節省量。缺少的快取節省量仍為未知。缺少的失敗類別中繼資料會回退至記錄的證據，如 [建置系統](#build-systems) 所述。資料保留政策不變。

## 警示與 Slack {#alerts-and-slack}

建立帶有數值指標且由 Grafana 管理的警示規則。例如：

| 指標 | 識別碼 | 範例條件 |
| --- | --- | --- |
| 建置成功率 | `success_rate` | 低於 99% |
| 失敗的建置 | `failed_builds` | 大於零 |
| 第 90 百分位數持續時間 | `p90` | 高於你團隊的持續時間上限 |

使用 **整個期間** 以取得評估視窗內的單一值，或將時間序列縮減為單一值。對於「整個期間」模式的持續時間查詢，請選擇一個序列。

- 使用固定的專案與篩選值。在背景警示評估期間無法使用儀表板變數。
- 對警示使用數值查詢。若要監控工作負載，請將建置健康度查詢篩選至該工作負載。
- 針對沒有建置或已回報快取節省量的間隔，設定規則的無資料行為。

設定 [Slack 聯絡點](https://grafana.com/docs/grafana/latest/alerting/configure-notifications/manage-contact-points/integrations/configure-slack/)，並透過 Grafana 的通知政策將規則路由至該聯絡點。Grafana 會傳送通知並儲存 Slack 憑證。

## 升級現有的儀表板 {#upgrading}

現有的持續時間面板會保留其查詢、篩選器、序列名稱與單位。已儲存的 Gradle 健康度面板與變數也能繼續運作。

匯入標準儀表板以使用共用的建置健康度查詢。現有的儀表板不會自動遷移。共用查詢需要提供建置健康度端點的 Tuist 伺服器；現有的持續時間查詢仍可在較舊的伺服器上運作。

## 需求 {#requirements}

- Grafana 10.4 或更新版本。
- 具有讀取你想要繪製圖表的專案與指標權限的 Tuist 權杖。請參閱下方的 [驗證](#authentication)。

## 驗證 {#authentication}

使用 <.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link> 進行儀表板與背景警示評估。授予 `project:builds:read` 以取得建置指標，並授予 `project:tests:read` 以取得測試持續時間，同時限制對你想要繪製圖表的專案的存取權限。僅需具備你所使用指標對應的範圍。依照 <.localized_link href="/guides/server/authentication#creating-an-account-token">權杖建立說明</.localized_link> 產生權杖。

此整合也接受現有專案權杖（用於其自有專案）以及具備使用者讀取權限的 <.localized_link href="/guides/server/authentication#as-a-user">使用者存取權杖</.localized_link>。使用者存取權杖效期較短。Grafana 會儲存你提供的權杖，但不會重新整理或重複使用你本機的 Tuist 登入狀態；請在權杖過期時更換。帳戶權杖讓你能獨立於使用者的登入工作階段，控制專案存取權、權限與效期。

## 設定 {#configuration}

新增資料來源並設定：

| 欄位 | 已儲存的設定 | 備註 |
| --- | --- | --- |
| 伺服器 URL | `jsonData.url` | 預設為 `https://tuist.dev`。 |
| 權杖 | `secureJsonData.apiToken` | Tuist 不記名權杖，以加密方式儲存。 |

選取 **儲存並測試** 以檢查連線。Grafana 會列出可存取的專案，然後針對第一個專案檢查建置與測試的讀取權限。

## 安裝 {#installation}

### 從 Grafana 目錄安裝 {#from-the-grafana-catalog}

發布後，像其他資料來源一樣從 **Connections → Add new connection → Tuist** 安裝，或使用 `grafana-cli plugins install tuist-metrics-datasource` 安裝。

### 在發布之前（自託管 Grafana）{#before-it-is-published-self-hosted-grafana}

外掛程式在獲得目錄核准之前尚未簽署。在自託管執行個體上，你可以：

- **允許未簽署的外掛程式** — 將 `tuist-metrics-datasource` 加入 `allow_loading_unsigned_plugins`（或 `GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=tuist-metrics-datasource`），並將建置好的外掛程式放入你的外掛程式目錄。
- **為你的執行個體私下簽署** — `npm run sign -- --rootUrls https://grafana.example.com`（URL 必須符合執行個體的 `root_url`），然後分發 zip 檔案。

[Grafana Cloud 要求使用來自目錄的外掛程式](https://grafana.com/docs/grafana-cloud/learn-and-build/get-started/learn/find-and-use-plugins/)，且不支援未簽署或手動上傳的外掛程式。
