---
{
  "title": "Bazel 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 喺團隊同 CI 之間共享 Bazel 遠端快取項目。"
}
---
# Bazel 快取 {#bazel-cache}

Tuist 提供一個 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 快取，Bazel 會將其連接為遠端快取。當某個動作的輸出已存在於快取中時，Bazel 會略過該動作，並從 Tuist 的快取中提取結果，從而節省團隊和 CI 環境中的編譯時間。如需 GitHub Actions 設定，請參閱 [Bazel on GitHub Actions](https://tuist.dev/solutions/bazel-github-actions)。如需了解遠端快取的運作方式，以及自託管快取與受管快取的比較，請參閱 [Bazel remote cache](https://tuist.dev/solutions/bazel-remote-cache)。

## 設定 {#setup}

在 Bazel 工作區的根目錄下執行：

```bash
tuist bazel setup
```

這會在你的 `.bazelrc` 旁邊寫入一個 `.bazelrc.tuist` 檔案，連接到最近的 Tuist 快取區域，並透過每個工作區專用的憑證輔助工具進行驗證。它還會在你的儲存庫的 `.bazelrc` 中加入一行 `try-import`：

```text
try-import %workspace%/.bazelrc.tuist
```

如果你想自行管理匯入，請傳遞 `--no-add-bazelrc-import`。

將 `.bazelrc.tuist` 加入你的 `.gitignore`，並在每台機器上執行設定，而不是將其提交到版本控制。生成的檔案會指向目前使用者的 Tuist 設定目錄下的絕對憑證輔助工具路徑，以及生成該檔案的機器最近的快取區域，因此這兩個值都不會轉移給隊友或持續整合執行器。請在 `.bazelrc` 中提交 `try-import` 這一行，因為它在每台機器上都相同。

當找不到 Bazel 工作區標記、檔案是符號連結，或已設定遠端快取或 Build Event Service 時，設定會保留現有的 `.bazelrc` 不變。這樣一來，再次執行它是冪等的。

執行一般的 Bazel 指令以驗證整合：

```bash
bazel build //...
```

快取活動隨後會出現在 Tuist 儀表板專案的 **Bazel Cache** 頁面中，該頁面顯示快取傳輸、下載和上傳、讀寫延遲、吞吐量以及動作快取命中率。專案 **Overview** 會提供相同的動作快取命中率摘要，並列出生成持續時間。

若要查看某個指令如何使用快取，請從 **Invocations** 開啟它。調用頁面會將動作快取查找與內容物件請求分開，讓你可以區分冷動作快取與緩慢的構件下載。

## 遠端執行 {#remote-execution}

Tuist 還可以在其 Linux 執行器上運行你的 Bazel 動作，因此快取未命中會在遠端運行，而不是在本機或 CI 執行器上運行。已啟用的帳戶可使用遠端執行功能；請 [email us](mailto:contact@tuist.dev) 或 [book a call](https://cal.tuist.dev/team/tuist/tuist) 以為你的帳戶啟用此功能。然後將 `--remote-execution` 傳遞給設定：

```bash
tuist bazel setup --remote-execution
```

設定隨後會在 `.bazelrc.tuist` 中將 Bazel 指向 Tuist 的執行器，位於遠端快取旁邊。它每次運行時都會查找目前的執行器和映像，因此請重新執行設定，而不是複製生成的值。動作使用執行器的 Linux 工具鏈運行，而不是你機器上安裝的工具，因此請在工作區中聲明你的動作所需的工具鏈。

設定還會將 `--jobs` 設為你的帳戶可以同時運行的遠端動作數量的兩倍，以便每個動作都有下一個動作等待執行。如果沒有這項設定，Bazel 會並行運行與機器核心數一樣多的動作，而 2 核心的 CI 執行器只會保持兩個遠端動作處於進行中狀態。

若要使用不同的值，請在命令列中傳遞 `--jobs`，或在 `try-import` 行之後的 `.bazelrc` 中進行設定。Bazel 會使用它讀取的最後一個值，因此該行之前的 `--jobs` 會被生成的值取代。

### 執行器大小 {#executor-sizes}

動作預設使用 4 GB 記憶體和 2 個 vCPU。設定 `tuist-memory-gb` 執行屬性以請求更大的 VM：

| `tuist-memory-gb` | 記憶體 | vCPU | 工作區磁碟 |
| --- | --- | --- | --- |
| `4`（預設） | 4 GB | 2 | 30 GB |
| `8` | 8 GB | 4 | 30 GB |
| `16` | 16 GB | 8 | 30 GB |

例如，在 `.bazelrc` 中的 `try-import` 行之後**添加**此行，以預設請求 8 GB：

```text
build --remote_default_exec_properties=tuist-memory-gb=8
```

對於單一目標，請在其 Bazel 規則中使用 `exec_properties = {"tuist-memory-gb": "8"}`。僅支援 `4`、`8` 和 `16`。較大的動作會按比例消耗更多帳戶分配的 vCPU 和記憶體限制，減少可以同時運行的數量。形狀必須符合這兩項限制。生成的 `--jobs` 使用預設形狀；如果需要請求更大的形狀，請覆蓋它。

執行器目前使用 Tuist 的 Linux amd64 映像。任意容器映像、其他執行作業系統和架構、持久性動作工作節點以及自帶執行器無法透過設定進行配置。請重新執行設定以獲取目前的映像和端點。

### 運行中的動作和使用量 {#running-actions-and-usage}

專案的 **Remote execution** 頁面顯示目前正在運行和已運行的內容：

- **Invocations** 首先列出正在運行的 Bazel 調用，每五秒刷新一次，顯示每個調用的運行時間以及其正在運行和排隊的遠端動作數量。一旦 Kura 獲得其目標模式，調用就會出現，並一直保留直到其完成報告到達。開啟其中一個會顯示其 **Executions**：正在 VM 中執行或等待 VM 的遠端動作，包括每個動作的助記符、目標、機器大小和目前狀態的時間。執行閘道在預先準備好的 VM 上運行的動作在運行期間不會列出；它們的時間數據會在調用完成後出現。當你搜尋或過濾清單時，不會顯示正在運行的調用。
- **Analytics** 以所選期間的 **Executions** 和 **Total execution time** 開頭，顯示與上一期間的變化以及隨時間變化的圖表。總執行時間是指每個動作的執行器在其 VM 中運行的時間，包括獲取輸入和上傳輸出，但不包括排隊或準備 VM 的時間。這是 **Usage** 頁面計費的時間。從快取提供的結果不屬於執行。

相同的數據可從 `GET /api/projects/{account_handle}/{project_handle}/remote-execution/activity` 和 `GET /api/projects/{account_handle}/{project_handle}/remote-execution/usage`（可選的 `from` 和 `to`，預設為過去 30 天，最多跨越 366 天）以及 `get_remote_execution_activity` 和 `get_remote_execution_usage` MCP 工具中獲取。

### 遠端動作時間 {#remote-action-timings}

**Analytics** 的其餘部分和 **Invocations** 表格涵蓋具有記錄遠端階段的動作：平均以及 p50/p90/p99 排隊和執行時間，並顯示與上一期間的變化、趨勢圖表，以及連結到每個調用的階段時間。按日期過濾（最多 90 天）。調用表格顯示每個調用的平均、p50 和 p90 執行時間。你可以按命令、目標或調用 ID 搜尋，按狀態、命令、目標或遠端動作數量過濾，並按除 Invocation 外的任何欄位排序。搜尋和表格過濾器僅適用於調用表格，不適用於分析數據。

開啟調用的 **Remote execution** 標籤頁以查看其 **Executions**，其遠端動作按持續時間（最長優先）或開始時間排序：每個遠端動作佔一行，顯示其相對於配置文件的開始時間、持續時間，以及分為排隊、輸入獲取、執行和輸出上傳時間的條形圖，比例縮放至頁面上最長的動作。將滑鼠懸停在條形圖上可查看每個階段的持續時間。該表格使用上傳的 Bazel 配置文件，並僅將伺服器階段與同一配置文件線程上明確無誤的動作關聯。

缺少時間數據表示 **Not recorded**，而非零。較舊的配置文件、缺少的動作間隔以及被 Bazel 省略的短階段可能會導致表格為空，即使發生了遠端工作。記錄的重試會在每個動作內累計。伺服器元數據可以描述快取結果，因此這些時間數據既不能證明是全新執行，也不屬於計費使用量。客戶端輸入上傳和本地執行輸出的上傳不包含在輸出上傳時間內。

相同的數據可從帶有 `remote_execution=true` 的構建步驟 REST 端點以及 `list_bazel_build_steps` / `get_bazel_build_step` MCP 工具中獲取。時間數據會與配置文件步驟一起保留 90 天。

### 檢查遠端動作 {#inspect-a-remote-action}

當 Tuist 的執行器記錄一個動作時，其在調用 **Remote execution** 標籤頁中的行會連結到該動作的頁面。**Overview** 顯示狀態和退出代碼、排隊、輸入獲取、執行和輸出上傳時間，動作是否已排程或在為該調用租用的工作節點上運行，以及工作節點、記憶體、超時和動作摘要。失敗的動作還會獲得一個 **Errors** 卡片：在其標準錯誤中識別的編譯器錯誤（Clang、GCC、Swift、javac、Go 和 rustc 格式）按文件分組，或者在無法識別時顯示其退出代碼和標準錯誤的結尾。**Logs** 在一個帶有行號的日誌中顯示標準輸出，隨後是標準錯誤，並高亮顯示錯誤行。就像 CI 作業日誌一樣，它會在結尾處打開，而 **Load earlier lines** 則向後分頁。記錄保留每個流的前 16 KiB；執行器還會將更長的流完整儲存為運行工件，因此日誌和 **Errors** 卡片涵蓋所有輸出。超過 16 MiB 的流僅保留其前 16 KiB 和最後 16 MiB。日誌中的標記顯示字節缺失的位置和原因：從非常長的流中跳過，或未儲存，例如副本已過期時。**Overview** 上的 **Command** 卡片顯示命令行（可透過 **Copy** 複製）、工作目錄和輸出路徑，以及摺疊部分中的環境和平台屬性。

名稱包含 `TOKEN`、`SECRET`、`PASSWORD` 或 `KEY` 的環境變數，以及以此方式命名的標誌的值，均顯示為 `****`。記錄僅供參考：沒有連結的行意味著沒有記錄明確匹配其輸出，並不表示動作在本地運行。記錄保留 90 天。REST 端點 `GET /api/projects/{account_handle}/{project_handle}/bazel/invocations/{invocation_id}/remote-actions` 和 `.../remote-actions/{operation_id}` 以及 `list_bazel_remote_actions` / `get_bazel_remote_action` MCP 工具返回相同的記錄；`.../remote-actions/{operation_id}/logs/{stdout|stderr}` 和 `get_bazel_remote_action_log` 按字節範圍讀取日誌。儲存的日誌副本是運行工件，並隨方案的運行工件窗口過期。

## 構建洞察 {#build-insights}

預設情況下，`tuist bazel setup` 也會配置 Bazel 的 Build Event Service，以便已完成的命令出現在 **Invocations** 儀表板上。請參閱 <.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link> 了解儀表板顯示的內容以及如何附加自定義元數據。

如果你只想要遠端快取而不希望發送構建事件流，請選擇退出：

```bash
tuist bazel setup --no-build-insights
```

## 持續整合 {#continuous-integration}

使用 <.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link> 中的一種方法對 CI 進行身份驗證，然後作為檢出步驟的一部分運行一次 `tuist bazel setup`，以便 `.bazelrc.tuist` 反映執行器的正確區域。請參閱 <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link> 獲取特定供應商的範例。

## 數據保留 {#data-retention}

Tuist 保留遠端快取觀察數據 90 天。請參閱 <.localized_link href="/guides/server/data-retention">data retention</.localized_link> 了解完整政策。
