---
{
  "title": "Bazel 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 在團隊與 CI 之間共享 Bazel 遠端快取項目。"
}
---
# Bazel 快取 {#bazel-cache}

Tuist 提供一個 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 快取，Bazel 可將其作為遠端快取連線。當動作的輸出已存在快取中時，Bazel 會略過該動作並從 Tuist 的快取拉取結果，為你的團隊與 CI 環境節省編譯時間。如需 GitHub Actions 設定，請參閱 [Bazel on GitHub Actions](https://tuist.dev/solutions/bazel-github-actions)。若要了解遠端快取的運作方式，以及自託管與受管快取的比較，請參閱 [Bazel remote cache](https://tuist.dev/solutions/bazel-remote-cache)。

## 設定 {#setup}

在 Bazel 工作區的根目錄執行：

```bash
tuist bazel setup
```

這會在你的 `.bazelrc` 旁邊寫入一個 `.bazelrc.tuist` 檔案，並連線至最近的 Tuist 快取區域，且透過每個工作區專屬的憑證輔助工具進行驗證。它也會在你的儲存庫的 `.bazelrc` 中加入一行 `try-import`：

```text
try-import %workspace%/.bazelrc.tuist
```

若你想自行管理匯入，請傳入 `--no-add-bazelrc-import`。

將 `.bazelrc.tuist` 加入你的 `.gitignore`，並在每台機器上執行設定，而不是將其提交到版本控制。產生的檔案會指向目前使用者的 Tuist 設定目錄下的絕對憑證輔助工具路徑，以及最接近產生該檔案之機器的快取區域，因此這些值不會轉移給隊友或持續整合執行器。請在 `.bazelrc` 中提交 `try-import` 這一行，因為它在每台機器上都相同。

當找不到 Bazel 工作區標記、檔案為符號連結，或已設定遠端快取或 Build Event Service 時，設定會保留現有的 `.bazelrc` 不變。這樣一來，再次執行設定是冪等的。

執行一般的 Bazel 指令以驗證整合：

```bash
bazel build //...
```

快取活動隨後會出現在 Tuist 儀表板專案的 **Bazel Cache** 頁面，顯示快取傳輸、下載與上傳、讀取與寫入延遲、吞吐量，以及動作快取命中率。專案的 **Overview** 會提供相同的動作快取命中率摘要，並與建置持續時間並列顯示。

若要查看某個指令如何使用快取，請從 **Invocations** 開啟。叫用頁面會將動作快取查詢與內容物件請求分開，讓你能分辨冷動作快取與緩慢的構件下載。

## 遠端執行 {#remote-execution}

Tuist 也能在其 Linux 執行器上執行你的 Bazel 動作，因此快取未命中會在遠端執行，而非在本機機器或 CI 執行器上執行。已啟用的帳戶可使用遠端執行功能；請 [email us](mailto:contact@tuist.dev) 或 [book a call](https://cal.tuist.dev/team/tuist/tuist) 以為你的帳戶啟用。接著在設定時傳入 `--remote-execution`：

```bash
tuist bazel setup --remote-execution
```

設定隨後會讓 Bazel 在 `.bazelrc.tuist` 中指向 Tuist 的執行器，位於遠端快取旁。每次執行時都會查找目前的執行器與映像檔，因此請重新執行設定，而不是複製產生的值。動作會使用執行器的 Linux 工具鏈執行，而非你機器上安裝的工具，因此請在工作區中宣告動作所需的工具鏈。

設定也會將 `--jobs` 設為你的帳戶可同時執行的遠端動作數量的兩倍，讓每個動作都有下一個動作等待執行。若不這麼做，Bazel 會平行執行與機器核心數相同數量的動作，而 2 核心的 CI 執行器只會讓兩個遠端動作處於進行中。

若要使用不同的值，請在命令列上傳入 `--jobs`，或在 `try-import` 行之後的 `.bazelrc` 中設定。Bazel 會使用最後讀取到的值，因此該行之前的 `--jobs` 會被產生的值取代。

### 執行器規格 {#executor-sizes}

動作預設使用 4 GB 記憶體與 2 個 vCPU。設定 `tuist-memory-gb` 執行屬性以請求更大的 VM：

| `tuist-memory-gb` | 記憶體 | vCPU | 工作區磁碟 |
| --- | --- | --- | --- |
| `4`（預設） | 4 GB | 2 | 30 GB |
| `8` | 8 GB | 4 | 30 GB |
| `16` | 16 GB | 8 | 30 GB |

例如，在 `.bazelrc` 中的 `try-import` 行之後**加入以下內容**，以預設請求 8 GB：

```text
build --remote_default_exec_properties=tuist-memory-gb=8
```

針對單一目標，請在其 Bazel 規則中使用 `exec_properties = {"tuist-memory-gb": "8"}`。僅支援 `4`、`8` 與 `16`。較大的動作會按比例消耗更多帳戶分配的 vCPU 與記憶體上限，減少可同時執行的數量。規格必須同時符合這兩項上限。產生的 `--jobs` 使用預設規格；若請求較大規格，請視需要覆寫它。

執行器目前使用 Tuist 的 Linux amd64 映像檔。任意容器映像檔、其他執行作業系統與架構、持久化動作工作節點，以及自備執行器，無法透過設定進行組態。請重新執行設定以取得目前的映像檔與端點。

### 執行中的動作與用量 {#running-actions-and-usage}

專案的 **Remote execution** 頁面顯示目前正在執行與已執行的內容：

- **Invocations** 會先列出正在執行的 Bazel 叫用，每五秒重新整理一次，並顯示每個叫用的執行時間，以及其遠端動作中有多少正在執行與排隊。一旦 Kura 取得其目標模式，叫用就會出現，並持續到其完成報告送達為止。開啟其中一個叫用會顯示其 **Executions**：首先是正在 VM 中執行或等待 VM 的遠端動作，接著是最近完成的 50 個動作及其結果（Passed、Cached、Failed 或 Error），每個動作都包含其助記符、目標、機器規格與截至目前為止的持續時間。剛完成的動作會顯示為 **Finishing**，最多一分鐘，直到其記錄送達為止。每一列都會開啟動作的頁面；當動作仍在執行時，頁面會顯示其狀態、機器與摘要，並在完成後載入完整記錄。執行閘道器在事先準備好的 VM 上執行的動作，在執行期間不會列出；它們會出現在已完成的動作中。當你搜尋或篩選清單時，不會顯示正在執行的叫用。
- **Analytics** 會先顯示所選期間的 **Executions** 與 **Total execution time**，並提供與上一期間的變化以及時間趨勢圖表。總執行時間是指每個動作的執行器在其 VM 中運行的時間，包括抓取輸入與上傳輸出，但不包含排隊或準備 VM 的時間。這是 **Usage** 頁面計費的時間。從快取提供的結果不屬於執行。

相同的資料可從 `GET /api/projects/{account_handle}/{project_handle}/remote-execution/activity` 與 `GET /api/projects/{account_handle}/{project_handle}/remote-execution/usage` 取得（可選的 `from` 與 `to`，預設為最近 30 天，最多涵蓋 366 天），以及從 `get_remote_execution_activity` 與 `get_remote_execution_usage` MCP 工具取得。

### 遠端動作計時 {#remote-action-timings}

**Analytics** 的其餘部分與 **Invocations** 表格涵蓋具有已記錄遠端階段的動作：平均與 p50/p90/p99 排隊與執行時間，並顯示與上一期間的變化、趨勢圖表，以及指向每個叫用階段計時的連結。依日期篩選（最多 90 天）。叫用表格會顯示每個叫用的平均、p50 與 p90 執行時間。你可以依命令、目標或叫用 ID 搜尋，依狀態、命令、目標或遠端動作數量篩選，並依除 Invocation 以外的任何欄位排序。搜尋與表格篩選僅適用於叫用表格，不適用於分析資料。

開啟叫用的 **Remote execution** 分頁以查看其 **Executions**，其中的遠端動作可依持續時間（最長者优先）或開始時間排序：每個遠端動作佔一列，顯示其相對於設定檔的開始時間、持續時間，以及一個拆分為排隊、輸入抓取、執行與輸出上傳時間的長條圖，並按比例縮放至頁面上最長的動作。將滑鼠懸停在長條上可查看每個階段的持續時間。該表格使用已上傳的 Bazel 設定檔，並將伺服器階段僅與同一設定檔執行緒中明確無歧義的動作關聯。

缺少計時表示 **Not recorded**，而非零。較舊的設定檔、缺少的動作間隔以及被 Bazel 省略的短暫階段，可能導致即使發生遠端工作，表格仍為空白。已記錄的重試會在每個動作內加總。伺服器後設資料可能描述快取結果，因此這些計時既非新鮮執行的證明，也非可計費的使用量。用戶端輸入上傳與本機執行輸出的上傳不包含在輸出上傳時間內。

相同的資料可從帶有 `remote_execution=true` 的建置步驟 REST 端點，以及 `list_bazel_build_steps` / `get_bazel_build_step` MCP 工具取得。計時資料會與設定檔步驟一起保留 90 天。

### 檢查遠端動作 {#inspect-a-remote-action}

當 Tuist 的執行器記錄一個動作時，其在叫用的 **Remote execution** 分頁中的列會連結至該動作的頁面。**Overview** 顯示狀態與退出碼、排隊、輸入抓取、執行與輸出上傳時間、動作是否已排程或在為該叫用租用的 worker 上執行、worker、記憶體、逾時與動作摘要。失敗的動作還會獲得一張 **Errors** 卡片：在其標準錯誤中識別出的編譯器錯誤（Clang、GCC、Swift、javac、Go 與 rustc 格式）按檔案分組；若無法識別，則顯示其退出碼與標準錯誤的結尾。**Logs** 在同一個日誌中顯示標準輸出，接著是標準錯誤，並附帶行號，高亮顯示錯誤行。如同 CI 工作日誌，它會開啟在末尾，而 **Load earlier lines** 可向後翻頁。記錄會保留每個串流的前 16 KiB；執行器也會將較長的串流完整儲存為運行產物，因此日誌與 **Errors** 卡片涵蓋所有輸出。超過 16 MiB 的串流僅保留其前 16 KiB 與最後 16 MiB。日誌中的標記會顯示位元組缺失的位置與原因：從非常長的串流中跳過，或未儲存，例如副本已過期時。**Overview** 上的 **Command** 卡片顯示命令行（可透過 **Copy** 複製）、工作目錄與輸出路徑，以及在摺疊區段中的環境與平台屬性。

名稱包含 `TOKEN`、`SECRET`、`PASSWORD` 或 `KEY` 的環境變數，以及以此方式命名的旗標值，會顯示為 `****`。記錄僅供參考：沒有連結的列表示沒有記錄能明確匹配其輸出，並非表示動作在本機執行。記錄會保留 90 天。REST 端點 `GET /api/projects/{account_handle}/{project_handle}/bazel/invocations/{invocation_id}/remote-actions` 與 `.../remote-actions/{operation_id}`，以及 `list_bazel_remote_actions` / `get_bazel_remote_action` MCP 工具會傳回相同的記錄；`.../remote-actions/{operation_id}/logs/{stdout|stderr}` 與 `get_bazel_remote_action_log` 則依位元組範圍讀取日誌。儲存的日誌副本屬於運行產物，並隨方案的運行產物視窗到期。

## 建置洞察 {#build-insights}

預設情況下，`tuist bazel setup` 也會設定 Bazel 的 Build Event Service，以便已完成的命令出現在 **Invocations** 儀表板上。請參閱 <.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link> 以了解儀表板顯示的內容以及如何附加自訂後設資料。

如果你只想要遠端快取，且不希望傳送建置事件串流，請使用以下選項退出：

```bash
tuist bazel setup --no-build-insights
```

## 持續整合 {#continuous-integration}

使用 <.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link> 中的一種方法對 CI 進行身分驗證，然後作為 checkout 步驟的一部分執行一次 `tuist bazel setup`，以便 `.bazelrc.tuist` 反映 runner 的正確區域。請參閱 <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link> 以獲取特定供應商的範例。

## 資料保留 {#data-retention}

Tuist 會保留遠端快取觀察資料 90 天。請參閱 <.localized_link href="/guides/server/data-retention">data retention</.localized_link> 以了解完整政策。
