---
{
  "title": "Bazel 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist，在團隊與 CI 之間共用 Bazel 遠端快取項目。"
}
---
# Bazel 快取 {#bazel-cache}

Tuist 提供一個 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 快取，Bazel 可將其作為遠端快取連接。當動作的輸出已存在於快取中時，Bazel 會跳過該動作並從 Tuist 的快取中提取結果，為你的團隊和 CI 環境節省編譯時間。若要設定 GitHub Actions，請參閱 [Bazel on GitHub Actions](https://tuist.dev/solutions/bazel-github-actions)。若要了解遠端快取的運作方式，以及自託管與受管快取的比較，請參閱 [Bazel remote cache](https://tuist.dev/solutions/bazel-remote-cache)。

## 設定 {#setup}

在 Bazel 工作區的根目錄下執行：

```bash
tuist bazel setup
```

這會在你的 `.bazelrc` 旁邊寫入一個 `.bazelrc.tuist` 檔案，連接到最近的 Tuist 快取區域，並透過每個工作區專屬的憑證輔助工具進行驗證。它還會在你的儲存庫的 `.bazelrc` 中加入一行 `try-import`：

```text
try-import %workspace%/.bazelrc.tuist
```

若你想自行管理匯入，請傳遞 `--no-add-bazelrc-import`。

將 `.bazelrc.tuist` 加入你的 `.gitignore`，並在每台機器上執行設定，而不是將其提交至版本控制。產生的檔案會指向目前使用者的 Tuist 設定目錄下的絕對憑證輔助工具路徑，以及最接近產生該檔案之機器的快取區域，因此這兩個值都不會轉移給隊友或持續整合執行器。請在 `.bazelrc` 中提交 `try-import` 這一行，因為它在每台機器上都相同。

當找不到 Bazel 工作區標記、檔案為符號連結，或已設定遠端快取或 Build Event Service 時，設定會保留現有的 `.bazelrc` 不變。這樣一來，再次執行它是冪等的。

執行一般的 Bazel 指令以驗證整合：

```bash
bazel build //...
```

快取活動隨後會出現在 Tuist 儀表板專案的 **Bazel Cache** 頁面中，該頁面顯示快取傳輸、下載和上傳、讀取和寫入延遲、吞吐量，以及動作快取命中率。專案 **Overview** 會提供相同的動作快取命中率摘要，並附上建置持續時間。

若要查看某個指令如何使用快取，請從 **Invocations** 開啟它。叫用頁面會將動作快取查詢與內容物件請求分開，讓你能夠分辨冷動作快取與緩慢的構件下載。

## 遠端執行 {#remote-execution}

Tuist 也可以在其 Linux 執行器上執行你的 Bazel 動作，因此快取未命中會在遠端執行，而不是在本機機器或 CI 執行器上執行。已啟用的帳戶可使用遠端執行功能；請 [email us](mailto:contact@tuist.dev) 或 [book a call](https://cal.tuist.dev/team/tuist/tuist) 以為你的帳戶啟用此功能。然後將 `--remote-execution` 傳遞給設定：

```bash
tuist bazel setup --remote-execution
```

設定隨後會在 `.bazelrc.tuist` 中將 Bazel 指向 Tuist 的執行器，位於遠端快取旁邊。它每次執行時都會查找目前的執行器和映像檔，因此請重新執行設定，而不是複製產生的值。動作使用執行器的 Linux 工具鏈執行，而非你機器上安裝的工具，因此請在工作區中宣告你的動作所需的工具鏈。

設定還會將 `--jobs` 設為你的帳戶一次可執行的遠端動作數量的兩倍，以便每個動作都有下一個動作等待執行。若沒有此設定，Bazel 會平行執行與機器核心數一樣多的動作，而 2 核心的 CI 執行器只會同時執行兩個遠端動作。

若要使用不同的值，請在命令列中傳遞 `--jobs`，或在 `try-import` 行之後的 `.bazelrc` 中設定它。Bazel 會使用它讀取的最後一個值，因此該行之前的 `--jobs` 會被產生的值取代。

### 執行器大小 {#executor-sizes}

動作預設使用 4 GB 記憶體和 2 個 vCPU。設定 `tuist-memory-gb` 執行屬性以請求更大的虛擬機器：

| `tuist-memory-gb` | 記憶體 | vCPU | 工作區磁碟 |
| --- | --- | --- | --- |
| `4`（預設） | 4 GB | 2 | 30 GB |
| `8` | 8 GB | 4 | 30 GB |
| `16` | 16 GB | 8 | 30 GB |

例如，在 `.bazelrc` 中的 `try-import` 行之後**新增**此行，以預設請求 8 GB：

```text
build --remote_default_exec_properties=tuist-memory-gb=8
```

對於單一目標，請在其 Bazel 規則中使用 `exec_properties = {"tuist-memory-gb": "8"}`。僅支援 `4`、`8` 和 `16`。較大的動作會按比例消耗更多帳戶分配的 vCPU 和記憶體限制，從而減少可同時執行的數量。形狀必須符合這兩項限制。產生的 `--jobs` 使用預設形狀；若請求較大形狀，請視需要覆寫它。

執行器目前使用 Tuist 的 Linux amd64 映像檔。任意容器映像檔、其他執行作業系統和架構、持久性動作工作節點，以及自帶執行器無法透過設定進行配置。請重新執行設定以取得目前的映像檔和端點。

### 執行中的動作和使用量 {#running-actions-and-usage}

專案的 **Remote execution** 頁面顯示目前正在執行和已執行的內容：

- **Invocations** 首先列出正在執行的 Bazel 叫用，每五秒刷新一次，顯示每個叫用的執行時間，以及其遠端動作中正在執行和排入佇列的數量。一旦 Kura 取得其目標模式，叫用就會出現，並持續直到其完成報告到達。開啟其中一個叫用會顯示其 **Executions**：正在虛擬機器中執行或等待虛擬機器的遠端動作，包含每個動作的助記符、目標、機器大小和目前狀態的時間。執行閘道在預先準備好的虛擬機器上執行的動作不會在執行期間列出；它們的時間資訊會在叫用完成後出現。當你搜尋或篩選清單時，不會顯示正在執行的叫用。
- **Analytics** 以所選期間的 **Executions** 和 **Total execution time** 開始，並顯示與上一期間的變化，按機器大小繪製圖表。總執行時間是指每個動作的執行器在其虛擬機器中運行的時間，包括獲取輸入和上傳輸出，但不包括排隊或準備虛擬機器的時間。這是 **Usage** 頁面計費的時間。從快取提供的結果不屬於執行。

相同的資料可從 `GET /api/projects/{account_handle}/{project_handle}/remote-execution/activity` 和 `GET /api/projects/{account_handle}/{project_handle}/remote-execution/usage`（可選的 `from` 和 `to`，預設為最後 30 天，最多跨越 366 天），以及從 `get_remote_execution_activity` 和 `get_remote_execution_usage` MCP 工具取得。

### 遠端動作時間 {#remote-action-timings}

**Analytics** 的其餘部分和 **Invocations** 表格涵蓋具有記錄遠端階段的動作：平均以及 p50/p90/p99 佇列和執行時間（含與上一期間的變化）、趨勢圖表，以及指向每個叫用階段時間的連結。依日期篩選（最多 90 天）。叫用表格顯示每個叫用的平均、p50 和 p90 執行時間。可依指令、目標或叫用 ID 搜尋，依狀態、指令、目標或遠端動作數量篩選，並依除「Invocation」以外的任何欄位排序。搜尋和表格篩選僅適用於叫用表格，不適用於分析資料。

開啟叫用的 **Remote execution** 分頁以查看其 **Executions**，這些遠端動作依持續時間（最長優先）或開始時間排序：每個遠端動作佔一行，顯示其相對於設定檔的開始時間、持續時間，以及分為佇列、輸入獲取、執行和輸出上傳時間的長條圖，並按比例縮放至頁面上最長的動作。將滑鼠懸停在長條上可查看每個階段的持續時間。該表格使用已上傳的 Bazel 設定檔，並將伺服器階段僅與同一設定檔執行緒中明確無誤的動作關聯。

缺少時間資訊表示 **Not recorded**，而非零。較舊的設定檔、缺少的動作間隔以及被 Bazel 省略的短暫階段，即使發生過遠端工作，也可能導致表格為空。記錄的重試會在每個動作內加總。伺服器中繼資料可以描述快取結果，因此這些時間資訊既非全新執行的證明，也非可計費的使用量。客戶端輸入上傳和本地執行輸出的上傳不包含在輸出上傳時間內。

相同的資料可從建置步驟 REST 端點取得（使用 `remote_execution=true`），以及透過 `list_bazel_build_steps` / `get_bazel_build_step` MCP 工具取得。時間資訊會與設定檔步驟一起保留 90 天。

## 建置洞察 {#build-insights}

預設情況下，`tuist bazel setup` 也會配置 Bazel 的 Build Event Service，以便已完成的指令出現在 **Invocations** 儀表板上。請參閱 <.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link> 以了解儀表板顯示的內容以及如何附加自訂中繼資料。

如果你只想要遠端快取而不想傳送建置事件串流，請使用以下選項退出：

```bash
tuist bazel setup --no-build-insights
```

## 持續整合 {#continuous-integration}

使用 <.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link> 中的其中一種方法對 CI 進行驗證，然後在檢出步驟中執行一次 `tuist bazel setup`，以便 `.bazelrc.tuist` 反映執行器所在的正確區域。請參閱 <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link> 以取得針對特定供應商的範例。

## 資料保留 {#data-retention}

Tuist 會保留遠端快取觀察資料 90 天。請參閱 <.localized_link href="/guides/server/data-retention">data retention</.localized_link> 以了解完整政策。
