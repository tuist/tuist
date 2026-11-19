---
{
  "title": "Bazel 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 喺你嘅團隊同 CI 之間共用 Bazel 遙距快取項目。"
}
---
# Bazel 快取 {#bazel-cache}

Tuist 提供一個 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 快取，Bazel 可將其連接為遠端快取。當某個動作的輸出已存在於快取中時，Bazel 會跳過該動作並從 Tuist 的快取中提取結果，從而節省團隊和 CI 環境中的編譯時間。如需 GitHub Actions 設定，請參閱 [Bazel on GitHub Actions](https://tuist.dev/solutions/bazel-github-actions)。如需了解遠端快取的工作原理，以及自託管快取與受管快取的比較，請參閱 [Bazel remote cache](https://tuist.dev/solutions/bazel-remote-cache)。

## 設定 {#setup}

在 Bazel workspace 的根目錄下執行：

```bash
tuist bazel setup
```

這會在你的 `.bazelrc` 旁邊寫入一個 `.bazelrc.tuist` 檔案，連接到最近的 Tuist 快取區域，並透過每個 workspace 的憑證輔助工具進行驗證。它還會在你的儲存庫的 `.bazelrc` 中加入一行 `try-import`：

```text
try-import %workspace%/.bazelrc.tuist
```

如果你想自行管理匯入，請傳遞 `--no-add-bazelrc-import`。

將 `.bazelrc.tuist` 加入你的 `.gitignore`，並在每台機器上執行設定，而不是將其提交到版本控制。產生的檔案指向當前使用者 Tuist 設定目錄下的絕對憑證輔助工具路徑，以及產生該檔案的機器最近的快取區域，因此這兩個值都不會轉移給隊友或持續整合執行器。請在 `.bazelrc` 中提交 `try-import` 行，因為它在每台機器上都是相同的。

當找不到 Bazel workspace 標記、檔案是符號連結，或已設定遠端快取或 Build Event Service 時，設定會保留現有的 `.bazelrc` 不變。這樣一來，再次執行它就是冪等的。

執行一般的 Bazel 命令以驗證整合：

```bash
bazel build //...
```

快取活動隨後會出現在 Tuist 儀表板專案的 **Bazel Cache** 頁面上，顯示快取傳輸、下載和上傳、讀寫延遲、吞吐量以及動作快取命中率。專案 **Overview** 會摘要相同的動作快取命中率以及建置持續時間。

若要查看某個命令如何使用快取，請從 **Invocations** 開啟它。調用頁面將動作快取查找與內容物件請求分開，讓你可以區分冷動作快取與緩慢的構件下載。

## 遠端執行 {#remote-execution}

Tuist 還可以在其 Linux 執行器上運行你的 Bazel 動作，因此快取未命中會在遠端運行，而不是在本機或 CI 執行器上運行。遠端執行適用於已啟用的帳戶；請 [email us](mailto:contact@tuist.dev) 或 [book a call](https://cal.tuist.dev/team/tuist/tuist) 以為你的帳戶啟用。然後將 `--remote-execution` 傳遞給設定：

```bash
tuist bazel setup --remote-execution
```

設定隨後會在 `.bazelrc.tuist` 中將 Bazel 指向 Tuist 的執行器，位於遠端快取旁邊。它每次運行時都會查找當前執行器和映像，因此請重新執行設定，而不是複製產生的值。動作使用執行器的 Linux 工具鏈運行，而不是你機器上安裝的工具，因此請在 workspace 中宣告你的動作所需的工具鏈。

設定還會將 `--jobs` 設為你的帳戶一次可以運行的遠端動作數量的兩倍，以便每個動作都有下一個動作等待。如果沒有這一點，Bazel 會並行運行與機器核心數一樣多的動作，而 2 核心的 CI 執行器只會保持兩個遠端動作處於進行中狀態。

若要使用不同的值，請在命令行上傳遞 `--jobs`，或在 `try-import` 行之後的 `.bazelrc` 中設定它。Bazel 使用它讀取的最後一個值，因此該行之前的 `--jobs` 會被產生的值取代。

### 執行器大小 {#executor-sizes}

動作預設使用 4 GB 記憶體和 2 個 vCPU。設定 `tuist-memory-gb` 執行屬性以請求更大的 VM：

| `tuist-memory-gb` | 記憶體 | vCPU | Workspace 磁碟 |
| --- | --- | --- | --- |
| `4`（預設） | 4 GB | 2 | 30 GB |
| `8` | 8 GB | 4 | 30 GB |
| `16` | 16 GB | 8 | 30 GB |

例如，在 `.bazelrc` 中的 `try-import` 行**之後**加入此行，以預設請求 8 GB：

```text
build --remote_default_exec_properties=tuist-memory-gb=8
```

對於單一目標，請在其 Bazel 規則中使用 `exec_properties = {"tuist-memory-gb": "8"}`。僅支援 `4`、`8` 和 `16`。較大的動作會按比例消耗更多帳戶分配的 vCPU 和記憶體限制，減少可以同時運行的數量。形狀必須符合這兩個限制。產生的 `--jobs` 使用預設形狀；如果需要請求更大形狀，請覆蓋它。

執行器目前使用 Tuist 的 Linux amd64 映像。任意容器映像、其他執行作業系統和架構、持久動作工作節點以及自帶執行器無法透過設定進行配置。重新執行設定以獲取當前映像和端點。

### 運行動作和使用量 {#running-actions-and-usage}

專案的 **Remote execution** 頁面顯示當前正在運行的內容和已運行的內容：

- **Invocations** 首先列出正在運行的 Bazel 調用，每五秒刷新一次，顯示每個調用已運行的時間以及其遠端動作正在運行和排隊的數量。一旦 Kura 擁有其目標模式，調用就會出現，並一直保留直到其完成報告到達。開啟一個調用會顯示其 **Executions**：正在 VM 中執行或等待 VM 的遠端動作，包括每個動作的助記符、目標、機器大小和當前狀態的時間。執行閘道在預先準備好的 VM 上運行的動作在運行時不會列出；它們的時間會在調用完成後顯示。當你搜索或過濾列表時，不會顯示正在運行的調用。
- **Analytics** 以所選期間的 **Executions** 和 **Total execution time** 開始，顯示與上一期間的變化以及隨時間變化的圖表。總執行時間是每個動作的執行器在其 VM 中運行的時間，包括獲取輸入和上傳輸出，但不包括排隊或準備 VM 的時間。這是 **Usage** 頁面計費的時間。從快取提供的結果不屬於執行。

相同數據可從 `GET /api/projects/{account_handle}/{project_handle}/remote-execution/activity` 和 `GET /api/projects/{account_handle}/{project_handle}/remote-execution/usage`（可選 `from` 和 `to`，預設為最後 30 天，最多跨越 366 天）以及 `get_remote_execution_activity` 和 `get_remote_execution_usage` MCP 工具獲得。

### 遠端動作時間 {#remote-action-timings}

**Analytics** 的其餘部分和 **Invocations** 表格涵蓋具有記錄遠端階段的動作：平均以及 p50/p90/p99 排隊和執行時間，並顯示與上一期間的變化、趨勢圖表，以及連結到每個調用的階段時間。按日期過濾（最多 90 天）。調用表格顯示每個調用的平均、p50 和 p90 執行時間。你可以按命令、目標或調用 ID 搜索，按狀態、命令、目標或遠端動作數量過濾，並按除 Invocation 外的任何列排序。搜索和表格過濾器僅適用於調用表格，不適用於分析數據。

開啟調用的 **Remote execution** 標籤頁以查看其 **Executions**，其遠端動作按持續時間（最長優先）或開始時間排序：每個遠端動作佔一行，顯示相對於配置文件的開始時間、持續時間，以及一個分為排隊、輸入獲取、執行和輸出上傳時間的條形圖，比例縮放至頁面上最長的動作。將鼠標懸停在條形圖上可查看每個階段的持續時間。該表格使用上傳的 Bazel 配置文件，並將伺服器階段僅與同一配置文件線程中明確無歧義的動作關聯。

缺少時間意味著 **Not recorded**，而非零。較舊的配置文件、缺少的動作間隔以及被 Bazel 省略的短階段可能會導致表格為空，即使發生了遠端工作。記錄的重試會在每個動作內累計。伺服器元數據可以描述快取結果，因此這些時間既不是新鮮執行的證明，也不是可計費的使用量。客戶端輸入上傳和本地執行輸出的上傳不包含在輸出上傳時間內。

相同數據可從帶有 `remote_execution=true` 的構建步驟 REST 端點以及 `list_bazel_build_steps` / `get_bazel_build_step` MCP 工具獲得。時間數據會與配置文件步驟一起保留 90 天。

## 構建洞察 {#build-insights}

預設情況下，`tuist bazel setup` 也會配置 Bazel 的 Build Event Service，以便已完成的命令出現在 **Invocations** 儀表板上。請參閱 <.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link> 了解儀表板顯示的內容以及如何附加自定義元數據。

如果你只想要遠端快取而不希望發送構建事件流，請使用以下命令退出：

```bash
tuist bazel setup --no-build-insights
```

## 持續集成 {#continuous-integration}

使用 <.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link> 中的一種方法對 CI 進行身份驗證，然後作為 checkout 步驟的一部分運行一次 `tuist bazel setup`，以便 `.bazelrc.tuist` 反映運行器的正確區域。請參閱 <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link> 獲取特定提供商的示例。

## 數據保留 {#data-retention}

Tuist 將遠端快取觀察數據保留 90 天。請參閱 <.localized_link href="/guides/server/data-retention">data retention</.localized_link> 了解完整政策。
