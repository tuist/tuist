---
{
  "title": "Bazel 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist，在團隊與 CI 之間共享 Bazel 遠端快取項目。"
}
---
# Bazel 快取 {#bazel-cache}

Tuist 提供一個 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 快取，Bazel 可將其作為遠端快取連線。當動作的輸出已存在於快取中時，Bazel 會略過該動作並從 Tuist 的快取中提取結果，為你的團隊與 CI 環境節省編譯時間。如需 GitHub Actions 設定，請參閱 [Bazel on GitHub Actions](https://tuist.dev/solutions/bazel-github-actions)。如需了解遠端快取的運作方式，以及自託管快取與受管快取的比較，請參閱 [Bazel remote cache](https://tuist.dev/solutions/bazel-remote-cache)。

## 設定 {#setup}

在 Bazel 工作區的根目錄執行：

```bash
tuist bazel setup
```

這會在你的 `.bazelrc` 旁邊寫入一個 `.bazelrc.tuist` 檔案，並連線至最近的 Tuist 快取區域，透過每個工作區專屬的憑證輔助工具進行驗證。它也會在你的儲存庫的 `.bazelrc` 中加入一行 `try-import`：

```text
try-import %workspace%/.bazelrc.tuist
```

若你想自行管理匯入，請傳入 `--no-add-bazelrc-import`。

將 `.bazelrc.tuist` 加入你的 `.gitignore`，並在每台機器上執行設定，而不是將其提交至版本控制。產生的檔案會指向目前使用者的 Tuist 設定目錄下的絕對憑證輔助工具路徑，以及最接近產生該檔案之機器的快取區域，因此這兩個值都不會轉移給隊友或持續整合執行器。請在 `.bazelrc` 中提交 `try-import` 這一行，因為它在每台機器上都相同。

當找不到 Bazel 工作區標記、檔案為符號連結，或已設定遠端快取或 Build Event Service 時，設定會保留現有的 `.bazelrc` 不變。如此一來，再次執行設定具有冪等性。

執行一般的 Bazel 指令以驗證整合：

```bash
bazel build //...
```

快取活動隨後會出現在 Tuist 儀表板專案的 **Bazel Cache** 頁面，顯示快取傳輸、下載與上傳、讀取與寫入延遲、吞吐量，以及動作快取命中率。專案的 **Overview** 會提供相同的動作快取命中率摘要，並同時顯示建置持續時間。

若要查看單一指令如何使用快取，請從 **Invocations** 開啟。叫用頁面會將動作快取查詢與內容物件請求分開，讓你能夠區分冷動作快取與緩慢的構件下載。

## 遠端執行 {#remote-execution}

Tuist 也能在其 Linux 執行器上執行你的 Bazel 動作，因此快取未命中會在遠端執行，而非在本機機器或 CI 執行器上執行。已啟用的帳戶可使用遠端執行功能；請 [email us](mailto:contact@tuist.dev) 或 [book a call](https://cal.tuist.dev/team/tuist/tuist) 以為你的帳戶啟用。然後將 `--remote-execution` 傳入設定：

```bash
tuist bazel setup --remote-execution
```

設定隨後會在 `.bazelrc.tuist` 中將 Bazel 指向 Tuist 的執行器，位於遠端快取旁邊。每次執行時都會查詢目前的執行器與映像檔，因此請重新執行設定，而不是複製產生的值。動作會使用執行器的 Linux 工具鏈執行，而非你機器上安裝的工具，因此請在工作區中宣告動作所需的工具鏈。

設定也會將 `--jobs` 設為你的帳戶可同時執行的遠端動作數量的兩倍，讓每個動作都有下一個動作等待執行。若不這麼做，Bazel 會根據機器的核心數平行執行盡可能多的動作，而 2 核心的 CI 執行器只會同時保持兩個遠端動作處於執行狀態。

若要使用不同的值，請在命令列上傳入 `--jobs`，或在 `try-import` 行之後的 `.bazelrc` 中設定。Bazel 會使用最後讀取的值，因此該行之前的 `--jobs` 會被產生的值取代。

### 執行器規格 {#executor-sizes}

動作預設使用 4 GB 記憶體與 2 個 vCPU。設定 `tuist-memory-gb` 執行屬性以請求更大的 VM：

| `tuist-memory-gb` | 記憶體 | vCPU | 工作區磁碟 |
| --- | --- | --- | --- |
| `4`（預設） | 4 GB | 2 | 30 GB |
| `8` | 8 GB | 4 | 30 GB |
| `16` | 16 GB | 8 | 30 GB |

例如，在 `.bazelrc` 中的 `try-import` 行之後**新增以下內容**，以預設請求 8 GB：

```text
build --remote_default_exec_properties=tuist-memory-gb=8
```

針對單一目標，請在其 Bazel 規則中使用 `exec_properties = {"tuist-memory-gb": "8"}`。僅支援 `4`、`8` 與 `16`。較大的動作會按比例消耗更多帳戶分配的 vCPU 與記憶體限制，減少可同時執行的數量。規格必須同時符合這兩項限制。產生的 `--jobs` 使用預設規格；若請求較大規格，請視需要覆寫它。

執行器目前使用 Tuist 的 Linux amd64 映像檔。任意容器映像檔、其他執行作業系統與架構、持久化動作工作節點，以及自帶執行器，無法透過設定進行配置。請重新執行設定以取得目前的映像檔與端點。

### 執行中的動作與用量 {#running-actions-and-usage}

專案的 **Remote execution** 頁面顯示目前執行中與已執行的內容：

- **Invocations** 會優先列出執行中的 Bazel 叫用，每五秒重新整理一次，顯示每個叫用的執行時間，以及其遠端動作的執行與佇列數量。當 Kura 取得目標模式時，叫用會出現，並持續到其完成報告到達為止。開啟叫用會顯示其 **Executions**：正在 VM 中執行或等待 VM 的遠端動作，包含每個動作的助記符、目標、機器規格與目前狀態的時間。由執行閘道在預先準備好的 VM 上執行的動作，在執行期間不會列出；其計時會在叫用完成後出現。搜尋或篩選清單時，不會顯示執行中的叫用。
- **Analytics** 以所選期間的 **Executions** 與 **Total execution time** 開頭，顯示與前一週期的變化以及隨時間變化的圖表。總執行時間是指每個動作的執行器在 VM 中運行的時間，包括抓取輸入與上傳輸出，但不包括佇列等待或準備 VM 的時間。這是 **Usage** 頁面計費的時間。從快取提供的結果不屬於執行。

相同資料可從 `GET /api/projects/{account_handle}/{project_handle}/remote-execution/activity` 與 `GET /api/projects/{account_handle}/{project_handle}/remote-execution/usage`（可選的 `from` 與 `to`，預設為最近 30 天，最多涵蓋 366 天），以及從 `get_remote_execution_activity` 與 `get_remote_execution_usage` MCP 工具取得。

### 遠端動作計時 {#remote-action-timings}

**Analytics** 的其餘部分與 **Invocations** 表格涵蓋具有記錄遠端階段的動作：平均與 p50/p90/p99 佇列及執行時間、與前一週期的變化、趨勢圖表，以及每個叫用階段計時的連結。依日期篩選（最多 90 天）。叫用表格顯示每個叫用的平均、p50 與 p90 執行時間。可依指令、目標或叫用 ID 搜尋，依狀態、指令、目標或遠端動作數量篩選，並依除 Invocation 外的任何欄位排序。搜尋與表格篩選僅適用於叫用表格，不適用於分析資料。

開啟叫用的 **Remote execution** 分頁以查看其 **Executions**，即依持續時間（最長優先）或開始時間排序的遠端動作：每個遠端動作佔一行，顯示相對於設定檔的開始時間、持續時間，以及分為佇列、輸入抓取、執行與輸出上傳時間的長條圖，並依頁面上最長的動作進行縮放。將滑鼠懸停在長條上可查看每個階段的持續時間。該表格使用已上傳的 Bazel 設定檔，並將伺服器階段僅與同一設定檔執行緒中明確無誤的動作關聯。

缺少計時表示 **Not recorded**，而非零。較舊的設定檔、缺少的動作間隔以及被 Bazel 省略的短暫階段，可能導致即使發生遠端工作，表格仍為空白。記錄的重試會在每個動作內加總。伺服器中繼資料可能描述快取結果，因此這些計時既非新鮮執行的證明，也非可計費用量。客戶端輸入上傳與本機執行輸出的上傳不包含在輸出上傳時間內。

相同資料可從帶有 `remote_execution=true` 的建置步驟 REST 端點，以及 `list_bazel_build_steps` / `get_bazel_build_step` MCP 工具取得。計時資料會與設定檔步驟一起保留 90 天。

## 建置洞察 {#build-insights}

預設情況下，`tuist bazel setup` 也會配置 Bazel 的 Build Event Service，以便已完成的指令出現在 **Invocations** 儀表板上。請參閱 <.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link> 以了解儀表板顯示的內容以及如何附加自訂中繼資料。

如果您只想要遠端快取而不希望傳送建置事件串流，請使用以下選項退出：

```bash
tuist bazel setup --no-build-insights
```

## 持續整合 {#continuous-integration}

使用 <.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link> 中的其中一種方法驗證 CI，然後作為 checkout 步驟的一部分執行一次 `tuist bazel setup`，以便 `.bazelrc.tuist` 反映執行器的正確區域。請參閱 <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link> 以取得特定供應商的範例。

## 資料保留 {#data-retention}

Tuist 會保留遠端快取觀察資料 90 天。請參閱 <.localized_link href="/guides/server/data-retention">data retention</.localized_link> 以了解完整政策。
