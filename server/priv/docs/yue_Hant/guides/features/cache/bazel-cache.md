---
{
  "title": "Bazel 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 同團隊同 CI 共用 Bazel 遙距快取項目。"
}
---
# Bazel 快取 {#bazel-cache}

Tuist 提供一個 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 快取，Bazel 會將其連接為遠端快取。當某個動作的輸出已存在於快取中時，Bazel 會略過該動作，並從 Tuist 的快取中提取結果，從而節省團隊及 CI 環境中的編譯時間。如需設定 GitHub Actions，請參閱 [Bazel on GitHub Actions](https://tuist.dev/solutions/bazel-github-actions)。如需了解遠端快取的運作方式，以及自託管快取與受管快取的比較，請參閱 [Bazel remote cache](https://tuist.dev/solutions/bazel-remote-cache)。

## 設定 {#setup}

在 Bazel 工作區的根目錄下執行：

```bash
tuist bazel setup
```

這會在你的 `.bazelrc` 旁邊寫入一個 `.bazelrc.tuist` 檔案，並連接到距離最近的 Tuist 快取區域，同時透過每個工作區專屬的憑證輔助程式進行驗證。它還會在你的儲存庫的 `.bazelrc` 中加入一行 `try-import`：

```text
try-import %workspace%/.bazelrc.tuist
```

如果你想自行管理匯入，請傳入 `--no-add-bazelrc-import`。

將 `.bazelrc.tuist` 加入你的 `.gitignore`，並在每台機器上執行設定，而不是將其提交到版本控制。產生的檔案會指向目前使用者的 Tuist 設定目錄下的絕對憑證輔助程式路徑，以及距離產生該檔案的機器最近的快取區域，因此這兩個值都不會轉移給隊友或持續整合執行器。請在 `.bazelrc` 中提交 `try-import` 這一行，因為它在每台機器上都相同。

當找不到 Bazel 工作區標記、檔案為符號連結，或已設定遠端快取或 Build Event Service 時，設定會保留現有的 `.bazelrc` 不變。這樣一來，再次執行設定具有冪等性。

執行一般的 Bazel 指令以驗證整合：

```bash
bazel build //...
```

快取活動隨後會出現在 Tuist 儀表板中專案的 **Bazel Cache** 頁面，該頁面顯示快取傳輸、下載和上傳、讀寫延遲、吞吐量以及動作快取命中率。專案的 **Overview** 則提供相同的動作快取命中率摘要，並附有建置持續時間。

若要查看某個指令如何使用快取，請從 **Invocations** 開啟它。叫用頁面會將動作快取查詢與內容物件請求分開，讓你能夠分辨冷動作快取與緩慢的構件下載。

## 遠端執行 {#remote-execution}

Tuist 亦可在其 Linux 執行器上運行你的 Bazel 動作，因此快取未命中會在遠端執行，而非在本機機器或 CI 執行器上執行。已啟用的帳戶可使用遠端執行功能；請 [電郵聯絡我們](mailto:contact@tuist.dev) 或 [預約通話](https://cal.tuist.dev/team/tuist/tuist) 以為你的帳戶啟用。然後在設定時傳入 `--remote-execution`：

```bash
tuist bazel setup --remote-execution
```

設定隨後會在 `.bazelrc.tuist` 中將 Bazel 指向 Tuist 的執行器，該檔案位於遠端快取旁。每次執行時都會查找目前的執行器和映像，因此請重新執行設定，而非複製產生的值。動作會使用執行器的 Linux 工具鏈運行，而非你機器上安裝的工具，因此請在工作區中宣告動作所需的工具鏈。

設定還會將 `--jobs` 設為你的帳戶可同時執行的遠端動作數量的兩倍，以便每個動作都有下一個動作等待執行。若無此設定，Bazel 會平行執行與機器核心數一樣多的動作，而雙核 CI 執行器只能同時保持兩個遠端動作處於執行狀態。

若要使用不同的值，請在命令列上傳入 `--jobs`，或在 `try-import` 行之後的 `.bazelrc` 中設定。Bazel 會使用最後讀取的值，因此該行之前的 `--jobs` 會被產生的值取代。

### 執行器規格 {#executor-sizes}

動作預設使用 4 GB 記憶體和 2 個 vCPU。設定 `tuist-memory-gb` 執行屬性以請求更小或更大的虛擬機器：

| `tuist-memory-gb` | 記憶體 | vCPU | 工作區磁碟 |
| --- | --- | --- | --- |
| `2` | 2 GB | 1 | 30 GB |
| `4`（預設） | 4 GB | 2 | 30 GB |
| `8` | 8 GB | 4 | 30 GB |
| `16` | 16 GB | 8 | 30 GB |

例如，在 `.bazelrc` 的 `try-import` 行之後**添加**以下內容，以預設請求 8 GB：

```text
build --remote_default_exec_properties=tuist-memory-gb=8
```

對於單一目標，請在其 Bazel 規則中使用 `exec_properties = {"tuist-memory-gb": "8"}`。僅支援 `2`、`4`、`8` 和 `16`。`2` 可在相同限制下同時執行兩倍數量的動作，但大型編譯器和連結器步驟可能會耗盡記憶體；請將這些目標改回 `4` 或更高。較大的動作會按比例消耗更多帳戶分配的 vCPU 和記憶體限制，從而減少可同時運行的數量。規格必須同時符合這兩項限制。產生的 `--jobs` 使用預設規格；如需請求更大規格，請視需要覆寫它。

執行器目前使用 Tuist 的 Linux amd64 映像。任意容器映像、其他執行作業系統和架構、持久化動作工作節點以及自帶執行器無法透過設定進行配置。請重新執行設定以獲取目前的映像和端點。

### 執行中的動作及使用量 {#running-actions-and-usage}

專案的 **Remote execution** 頁面顯示目前正在運行及已運行的內容：

- **Invocations** 首先列出正在運行的 Bazel 叫用，每五秒刷新一次，並顯示每個叫用的運行時間及其遠端動作的運行和排隊數量。一旦 Kura 取得其目標模式，叫用便會出現，並持續顯示直到收到其完成報告。開啟叫用會顯示其 **Executions**：首先是正在虛擬機器中執行或等待虛擬機器的遠端動作，然後是最近完成的 50 個動作及其結果（通過、快取、失敗或錯誤），每個動作都包含其助記符、目標、機器規格和迄今為止的持續時間。剛完成的動作會顯示為 **Finishing**，最多持續一分鐘，直到其記錄到達。每一行都會開啟動作的頁面；當動作仍在運行時，頁面會顯示其狀態、機器和摘要，並在完成後載入完整記錄。執行閘道在預先準備好的虛擬機器上運行的動作不會在運行時列出；它們會出現在已完成的動作中。當你搜尋或篩選列表時，不會顯示正在運行的叫用。
- **Analytics** 以所選期間的 **Executions** 和 **Total execution time** 開頭，並顯示與上一期間的變化及隨時間變化的圖表。總執行時間是指每個動作的執行器在其虛擬機器中運行的時間，包括獲取輸入和上傳輸出，但不包括排隊或準備虛擬機器的時間。這是 **Usage** 頁面計費的時間。從快取提供的結果不屬於執行。

相同數據可從 `GET /api/projects/{account_handle}/{project_handle}/remote-execution/activity` 和 `GET /api/projects/{account_handle}/{project_handle}/remote-execution/usage`（可選 `from` 和 `to`，預設為過去 30 天，最多涵蓋 366 天）以及 `get_remote_execution_activity` 和 `get_remote_execution_usage` MCP 工具獲得。

### 遠端動作計時 {#remote-action-timings}

**Analytics** 的其餘部分和 **Invocations** 表格涵蓋具有記錄遠端階段的動作：平均及 p50/p90/p99 排隊和執行時間，連同與上一期間的變化、趨勢圖表，以及每個叫用的階段計時連結。按日期篩選（最多 90 天）。叫用表格顯示每個叫用的平均、p50 和 p90 執行時間。你可以按指令、目標或叫用 ID 搜尋，按狀態、指令、目標或遠端動作數量篩選，並按除 Invocation 外的任何欄位排序。搜尋和表格篩選僅適用於叫用表格，不適用於分析數據。

開啟叫用的 **Remote execution** 分頁以查看其 **Executions**，其遠端動作按持續時間（最長優先）或開始時間排序：每個遠端動作佔一行，顯示其相對於配置文件的開始時間、持續時間，以及分為排隊、輸入獲取、執行和輸出上傳時間的條形圖，比例基於頁面上最長的動作。將滑鼠懸停在條形圖上可查看每個階段的持續時間。該表格使用上傳的 Bazel 配置文件，並將伺服器階段僅與同一配置文件線程中明確無歧義的動作關聯。

缺少計時表示 **Not recorded**，而非零。較舊的配置文件、缺少的動作間隔以及被 Bazel 省略的短階段可能導致表格為空，即使發生了遠端工作。記錄的重試會在每個動作內累計。伺服器元數據可以描述快取結果，因此這些計時既不是新鮮執行的證明，也不是可計費的使用量。客戶端輸入上傳和本地執行輸出的上傳不包含在輸出上傳時間內。

相同數據可從帶有 `remote_execution=true` 的構建步驟 REST 端點以及 `list_bazel_build_steps` / `get_bazel_build_step` MCP 工具獲得。計時數據會與配置文件步驟一起保留 90 天。

### 檢查遠端動作 {#inspect-a-remote-action}

當 Tuist 的執行器記錄一個動作時，其在叫用的 **Remote execution** 分頁中的行會連結到該動作的頁面。**Overview** 顯示狀態和退出代碼、排隊、輸入獲取、執行和輸出上傳時間，動作是否被調度或在為該叫用租賃的工作節點上運行，以及工作節點、記憶體、超時和動作摘要。失敗的動作還會獲得一個 **Errors** 卡片：在其標準錯誤中識別出的編譯器錯誤（Clang、GCC、Swift、javac、Go 和 rustc 格式）按文件分組，或者在無法識別時顯示其退出代碼和標準錯誤的末尾。**Logs** 在一個帶有行號的日誌中顯示標準輸出，隨後是標準錯誤，並突出顯示錯誤行。就像 CI 作業日誌一樣，它會在末尾打開，而 **Load earlier lines** 則向後分頁。記錄保留每個流的前 16 KiB；執行器還將更長的流完整存儲為運行工件，因此日誌和 **Errors** 卡片涵蓋所有輸出。超過 16 MiB 的流僅保留其前 16 KiB 和最後 16 MiB。日誌中的標記顯示缺少字節的位置和原因：從非常長的流中跳過，或未存儲，例如一旦副本已過期。**Overview** 上的 **Command** 卡片顯示命令行（可通過 **Copy** 複製）、工作目錄和輸出路徑，以及摺疊部分中的環境和平台屬性。

名稱包含 `TOKEN`、`SECRET`、`PASSWORD` 或 `KEY` 的環境變數，以及以此方式命名的標誌的值，顯示為 `****`。記錄僅供參考：沒有連結的行意味著沒有記錄明確匹配其輸出，並不表示動作在本地運行。記錄保留 90 天。REST 端點 `GET /api/projects/{account_handle}/{project_handle}/bazel/invocations/{invocation_id}/remote-actions` 和 `.../remote-actions/{operation_id}` 以及 `list_bazel_remote_actions` / `get_bazel_remote_action` MCP 工具返回相同的記錄；`.../remote-actions/{operation_id}/logs/{stdout|stderr}` 和 `get_bazel_remote_action_log` 按字節範圍讀取日誌。存儲的日誌副本是運行工件，並隨方案的運行工件窗口過期。

## 構建洞察 {#build-insights}

預設情況下，`tuist bazel setup` 也會配置 Bazel 的 Build Event Service，以便完成的命令出現在 **Invocations** 儀表板上。請參閱 <.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link> 以了解儀表板顯示的內容以及如何附加自定義元數據。

如果你只想要遠端快取而不希望發送構建事件流，請選擇退出：

```bash
tuist bazel setup --no-build-insights
```

## 持續整合 {#continuous-integration}

使用 <.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link> 中的一種方法對 CI 進行身份驗證，然後作為 checkout 步驟的一部分運行一次 `tuist bazel setup`，以便 `.bazelrc.tuist` 反映運行器的正確區域。請參閱 <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link> 以獲取特定提供商的範例。

## 數據保留 {#data-retention}

Tuist 將遠端快取觀察數據保留 90 天。請參閱 <.localized_link href="/guides/server/data-retention">data retention</.localized_link> 以了解完整政策。
