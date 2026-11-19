---
{
  "title": "Bazel 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist，喺你嘅團隊同 CI 之間共用 Bazel 遠端快取項目。"
}
---
# Bazel 快取 {#bazel-cache}

Tuist 提供一個 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 快取，Bazel 可將其連接為遠端快取。當某個動作的輸出已存在於快取中時，Bazel 會略過該動作並從 Tuist 的快取拉取結果，從而節省團隊與 CI 環境中的編譯時間。如需 GitHub Actions 設定，請參閱 [Bazel on GitHub Actions](https://tuist.dev/solutions/bazel-github-actions)。如需了解遠端快取的運作方式，以及自託管快取與受管快取的比較，請參閱 [Bazel remote cache](https://tuist.dev/solutions/bazel-remote-cache)。

## 設定 {#setup}

在 Bazel 工作區的根目錄執行：

```bash
tuist bazel setup
```

這會在你的 `.bazelrc` 旁邊寫入一個 `.bazelrc.tuist` 檔案，並連接到最近的 Tuist 快取區域，同時透過每個工作區專屬的憑證輔助工具進行驗證。它也會在你的儲存庫的 `.bazelrc` 中加入一行 `try-import`：

```text
try-import %workspace%/.bazelrc.tuist
```

如果你想自行管理匯入，請傳入 `--no-add-bazelrc-import`。

將 `.bazelrc.tuist` 加入你的 `.gitignore`，並在每台機器上執行設定，而不是將其提交到版本控制。產生的檔案會指向目前使用者的 Tuist 設定目錄下的絕對憑證輔助工具路徑，以及最接近產生該檔案之機器的快取區域，因此這兩個值都不會轉移給隊友或持續整合執行器。請在 `.bazelrc` 中提交 `try-import` 這一行，因為它在每台機器上都相同。

當找不到 Bazel 工作區標記、檔案為符號連結，或已設定遠端快取或 Build Event Service 時，設定會保留現有的 `.bazelrc` 不變。這樣一來，再次執行設定就是冪等的。

執行一般的 Bazel 指令以驗證整合：

```bash
bazel build //...
```

快取活動隨後會出現在 Tuist 儀表板中專案的 **Bazel Cache** 頁面，顯示快取傳輸、下載與上傳、讀寫延遲、吞吐量，以及動作快取命中率。專案的 **Overview** 會提供相同的動作快取命中率摘要，並與建置持續時間並列顯示。

若要查看單一指令如何使用快取，請從 **Invocations** 開啟它。叫用頁面會將動作快取查詢與內容物件請求分開，讓你能分辨冷動作快取與緩慢的構件下載。

## 遠端執行 {#remote-execution}

Tuist 亦可在其 Linux 執行器上執行你的 Bazel 動作，因此快取未命中會在遠端執行，而非在本機機器或 CI 執行器上執行。已啟用的帳戶可使用遠端執行功能；請 [email us](mailto:contact@tuist.dev) 或 [book a call](https://cal.tuist.dev/team/tuist/tuist) 以為你的帳戶啟用。然後將 `--remote-execution` 傳入設定：

```bash
tuist bazel setup --remote-execution
```

設定隨後會讓 Bazel 指向 `.bazelrc.tuist` 中的 Tuist 執行器，位於遠端快取旁邊。每次執行時都會查找目前的執行器與映像檔，因此請重新執行設定，而非複製產生的值。動作會使用執行器的 Linux 工具鏈執行，而非你機器上安裝的工具，因此請在工作區中宣告你的動作所需的工具鏈。

設定也會將 `--jobs` 設為你的帳戶可同時執行的遠端動作數量的兩倍，讓每個動作都有下一個動作等待執行。若不如此設定，Bazel 會平行執行與機器核心數相同數量的動作，而一台 2 核心的 CI 執行器只會同時保持兩個遠端動作處於執行中。

若要使用不同的值，請在命令列上傳入 `--jobs`，或在 `try-import` 行之後的 `.bazelrc` 中設定。Bazel 會使用它讀取的最後一個值，因此該行之前的 `--jobs` 會被產生的值取代。

### 執行器規格 {#executor-sizes}

動作預設使用 4 GB 記憶體與 2 個 vCPU。設定 `tuist-memory-gb` 執行屬性以請求更大的 VM：

| `tuist-memory-gb` | 記憶體 | vCPU | 工作區磁碟 |
| --- | --- | --- | --- |
| `4`（預設） | 4 GB | 2 | 30 GB |
| `8` | 8 GB | 4 | 30 GB |
| `16` | 16 GB | 8 | 30 GB |

例如，在 `.bazelrc` 的 `try-import` 行之後加入以下內容，以預設請求 8 GB：**after**

```text
build --remote_default_exec_properties=tuist-memory-gb=8
```

對於單一目標，請在其 Bazel 規則中使用 `exec_properties = {"tuist-memory-gb": "8"}`。僅支援 `4`、`8` 與 `16`。較大的動作會按比例消耗更多帳戶分配的 vCPU 與記憶體上限，減少可同時執行的數量。規格必須同時符合這兩項上限。產生的 `--jobs` 使用預設規格；如需請求更大規格，請視需要覆寫它。

執行器目前使用 Tuist 的 Linux amd64 映像檔。任意容器映像檔、其他執行作業系統與架構、持久化動作工作節點，以及自帶執行器，無法透過設定進行配置。請重新執行設定以取得目前的映像檔與端點。

### 執行中的動作與用量 {#running-actions-and-usage}

專案的 **Remote execution** 頁面顯示目前正在執行與已執行的內容：

- **Invocations** 會優先列出正在執行的 Bazel 叫用，每五秒刷新一次，顯示每個叫用的執行時間，以及其遠端動作中正在執行與排隊的數量。當 Kura 取得目標模式後，叫用就會出現，並持續顯示直到收到其完成報告為止。開啟任一叫用會顯示其 **Executions**：正在 VM 中執行或等待 VM 的遠端動作，包含每個動作的助記符、目標、機器規格及其目前狀態的時間。由執行閘道在事先準備好的 VM 上執行的動作，在執行期間不會列出；其時間數據會在叫用完成後顯示。當你搜尋或過濾清單時，不會顯示正在執行的叫用。
- **Analytics** 以所選期間的 **Executions** 與 **Total execution time** 開頭，並顯示相較於上一期間的變化，按機器規格繪製圖表。總執行時間是指每個動作的執行器在其 VM 中運行的時間，包括抓取輸入與上傳輸出，但不包括排隊或準備 VM 的時間。這是 **Usage** 頁面計費的時間。從快取提供的結果不屬於執行。

相同數據可從 `GET /api/projects/{account_handle}/{project_handle}/remote-execution/activity` 與 `GET /api/projects/{account_handle}/{project_handle}/remote-execution/usage` 取得（可選 `from` 與 `to`，預設為最近 30 天，最多涵蓋 366 天），以及從 `get_remote_execution_activity` 與 `get_remote_execution_usage` MCP 工具取得。

### 遠端動作時間 {#remote-action-timings}

**Analytics** 的其餘部分與 **Invocations** 表格涵蓋已記錄遠端階段的動作：平均及 p50/p90/p99 排隊與執行時間，連同相較於上一期間的變化、趨勢圖表，以及指向每個叫用階段時間的連結。可按日期過濾（最多 90 天）。叫用表格顯示每個叫用的平均、p50 及 p90 執行時間。你可按指令、目標或叫用 ID 搜尋，按狀態、指令、目標或遠端動作數量過濾，並按除 Invocation 外的任何欄位排序。搜尋與表格過濾僅適用於叫用表格，不適用於分析數據。

開啟叫用的 **Remote execution** 分頁以查看其 **Executions**，即按持續時間（最長優先）或開始時間排序的遠端動作：每個遠端動作佔一行，顯示其相對於設定檔的開始時間、持續時間，以及分為排隊、輸入抓取、執行與輸出上傳時間的長條圖，比例依據頁面上最長的動作調整。將滑鼠懸停在長條上可查看每個階段的持續時間。該表格使用已上傳的 Bazel 設定檔，並將伺服器階段僅關聯到同一設定檔執行緒中明確無歧義的動作。

缺少時間數據表示 **Not recorded**，而非零。較舊的設定檔、缺失的動作間隔以及被 Bazel 省略的短暫階段，可能導致表格為空，即使曾發生遠端工作。記錄的重試會在每個動作內累計。伺服器元數據可能描述快取結果，因此這些時間數據既非新鮮執行的證明，亦非可計費用量。客戶端輸入上傳與本地執行輸出的上傳不包含在輸出上傳時間內。

相同數據可從帶有 `remote_execution=true` 的構建步驟 REST 端點，以及 `list_bazel_build_steps` / `get_bazel_build_step` MCP 工具取得。時間數據會隨設定檔步驟保留 90 天。

## 構建洞察 {#build-insights}

預設情況下，`tuist bazel setup` 也會配置 Bazel 的 Build Event Service，以便已完成的指令出現在 **Invocations** 儀表板上。請參閱 <.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link> 以了解儀表板顯示的內容及如何附加自定義元數據。

如果你只想要遠端快取而不希望發送構建事件流，請選擇退出：

```bash
tuist bazel setup --no-build-insights
```

## 持續整合 {#continuous-integration}

使用 <.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link> 中的其中一種方法對 CI 進行身份驗證，然後作為檢出步驟的一部分運行一次 `tuist bazel setup`，以便 `.bazelrc.tuist` 反映執行器的正確區域。請參閱 <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link> 以獲取特定供應商的示例。

## 數據保留 {#data-retention}

Tuist 會保留遠端快取觀察數據 90 天。請參閱 <.localized_link href="/guides/server/data-retention">data retention</.localized_link> 以了解完整政策。
