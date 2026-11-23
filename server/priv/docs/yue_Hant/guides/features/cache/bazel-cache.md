---
{
  "title": "Bazel 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 同團隊同 CI 共用 Bazel 遙距快取項目。"
}
---
# Bazel 快取 {#bazel-cache}

Tuist 提供一個 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 快取，Bazel 可將其連接為遠端快取。當某個動作的輸出已存在於快取中時，Bazel 會跳過該動作並從 Tuist 的快取中提取結果，從而節省團隊和 CI 環境中的編譯時間。如需 GitHub Actions 設定，請參閱 [Bazel on GitHub Actions](https://tuist.dev/solutions/bazel-github-actions)。如需了解遠端快取的運作方式，以及自託管與受管快取的比較，請參閱 [Bazel remote cache](https://tuist.dev/solutions/bazel-remote-cache)。

## 設定 {#setup}

在 Bazel workspace 的根目錄下執行：

```bash
tuist bazel setup
```

這會在你的 `.bazelrc` 旁邊寫入一個 `.bazelrc.tuist` 檔案，連接到最近的 Tuist 快取區域，並透過每個 workspace 的憑證輔助程式進行驗證。它還會在你的儲存庫的 `.bazelrc` 中加入一行 `try-import`：

```text
try-import %workspace%/.bazelrc.tuist
```

如果你想自行管理匯入，請傳遞 `--no-add-bazelrc-import`。

將 `.bazelrc.tuist` 加入你的 `.gitignore`，並在每台機器上執行設定，而不是將其提交。產生的檔案會指向目前使用者的 Tuist 設定目錄下的絕對憑證輔助程式路徑，以及最接近產生該檔案的機器的快取區域，因此這兩個值都不會轉移給隊友或持續整合執行器。請在 `.bazelrc` 中提交 `try-import` 行，這在每台機器上都是相同的。

當找不到 Bazel workspace 標記、檔案是符號連結，或已設定遠端快取或 Build Event Service 時，設定會保留現有的 `.bazelrc` 不變。這樣一來，再次執行它就是冪等的。

執行一般的 Bazel 指令以驗證整合：

```bash
bazel build //...
```

快取活動隨後會出現在 Tuist 儀表板的專案 **Bazel Cache** 頁面中，顯示快取傳輸、下載和上傳、讀寫延遲、吞吐量，以及動作快取命中率。專案 **Overview** 會提供相同動作快取命中率的摘要，並列出生成持續時間。

若要查看某個指令如何使用快取，請從 **Invocations** 開啟它。叫用頁面會將動作快取查詢與內容物件請求分開，讓你可以區分冷動作快取與緩慢的構件下載。

## 遠端執行 {#remote-execution}

Tuist 還可以在其 Linux 執行器上執行你的 Bazel 動作，因此快取未命中會在遠端執行，而不是在本機或 CI 執行器上執行。已啟用的帳戶可使用遠端執行功能；請 [email us](mailto:contact@tuist.dev) 或 [book a call](https://cal.tuist.dev/team/tuist/tuist) 以為你的帳戶啟用此功能。然後將 `--remote-execution` 傳遞給設定：

```bash
tuist bazel setup --remote-execution
```

設定隨後會將 Bazel 指向 `.bazelrc.tuist` 中的 Tuist 執行器，位於遠端快取旁邊。它每次執行時都會查找目前的執行器和映像，因此請重新執行設定，而不是複製產生的值。動作使用執行器的 Linux 工具鏈執行，而非你機器上安裝的工具，因此請在 workspace 中宣告你的動作所需的工具鏈。

設定還會將 `--jobs` 設為你的帳戶一次可執行的遠端動作數量的兩倍，以便每個動作都有下一個動作等待執行。否則，Bazel 會平行執行與機器核心數一樣多的動作，而 2 核心的 CI 執行器只會保持兩個遠端動作處於執行中狀態。

若要使用不同的值，請在命令列中傳遞 `--jobs`，或在 `try-import` 行之後的 `.bazelrc` 中設定它。Bazel 會使用它讀取的最後一個值，因此該行之前的 `--jobs` 會被產生的值取代。

### 執行器大小 {#executor-sizes}

動作預設使用 2 GB 記憶體和 1 個 vCPU，這適合單執行緒編譯動作。設定 `tuist-memory-gb` 執行屬性以請求更大的 VM，用於多執行緒測試或耗費記憶體的連結：

| `tuist-memory-gb` | 記憶體 | vCPU | 工作區磁碟 |
| --- | --- | --- | --- |
| `2`（預設） | 2 GB | 1 | 30 GB |
| `4` | 4 GB | 2 | 30 GB |
| `8` | 8 GB | 4 | 30 GB |
| `16` | 16 GB | 8 | 30 GB |

例如，在 `.bazelrc` 中的 `try-import` 行**之後**加入以下內容，以預設請求 8 GB：

```text
build --remote_default_exec_properties=tuist-memory-gb=8
```

針對單一目標，請在其 Bazel 規則中改用 `exec_properties = {"tuist-memory-gb": "8"}`。只支援 `4`、`8` 和 `16`。較大的動作會按比例消耗帳戶分配的 vCPU 和記憶體上限，減少可同時執行的數量。形狀必須同時符合兩項限制。產生的 `--jobs` 使用預設形狀；如需請求較大形狀，可按需要覆寫它。

執行器目前使用 Tuist 的 Linux amd64 映像檔。任意容器映像檔、其他執行作業系統與架構、持久化動作工作節點，以及自帶執行器，均無法透過設定進行配置。請重新執行設定以取得目前的映像檔和端點。

### 執行中的動作與用量 {#running-actions-and-usage}

專案的**遠端執行**頁面會顯示目前正在執行及已執行的內容：

- **叫用**會優先列出正在執行的 Bazel 叫用，每五秒重新整理一次，並顯示每個叫用的執行時間，以及其遠端動作中正在執行和排队的數量。當 Kura 取得目標模式後，叫用就會出現，並持續顯示直到收到其完成報告為止。開啟任一叫用會顯示其**執行**：首先是正在 VM 中執行或等待 VM 的遠端動作，然後是最近完成的 50 個動作及其結果（通過、快取、失敗或錯誤），每個動作都包含其助記符、目標、機器大小和迄今為止的持續時間。剛完成的動作會顯示為**完成中**，最多一分鐘，直到其記錄到達為止。每一列都會開啟該動作的頁面；當動作仍在執行時，頁面會顯示其狀態、機器和摘要，並在完成後載入完整記錄。執行閘道在預先準備好的 VM 上執行的動作，在執行期間不會列出；它們會出現在已完成的動作中。當你搜尋或篩選清單時，不會顯示正在執行的叫用。
- **分析**會先顯示所選期間的**執行**和**總執行時間**，並提供與上一期間的變化及時間趨勢圖表。總執行時間是指每個動作的執行器在其 VM 中運行的時間，包括擷取輸入和上傳輸出，但不包括排隊或準備 VM 的時間。這是**用量**頁面計費的時間。從快取提供的結果不屬於執行。

相同資料可從 `GET /api/projects/{account_handle}/{project_handle}/remote-execution/activity` 和 `GET /api/projects/{account_handle}/{project_handle}/remote-execution/usage` 取得（可選 `from` 和 `to`，預設為過去 30 天，最多涵蓋 366 天），以及從 `get_remote_execution_activity` 和 `get_remote_execution_usage` MCP 工具取得。

### 遠端動作計時 {#remote-action-timings}

**分析**的其餘部分同**叫用**表格涵蓋咗有記錄遠端階段嘅動作：包括平均同 p50/p90/p99 排隊同執行時間，連同相比上一期間嘅變化、趨勢圖表，以及指向每個叫用階段計時嘅連結。可以按日期篩選（最多 90 日）。叫用表格會顯示每個叫用的平均、p50 同 p90 執行時間。你可以按指令、目標或叫用 ID 搜尋，按狀態、指令、目標或遠端動作數量篩選，並可按除咗叫用之外嘅任何欄位排序。搜尋同表格篩選只適用於叫用表格，不適用於分析數據。

開啟叫用的**遠端執行**分頁以查看其**執行**，當中遠端動作會按持續時間（最長優先）或開始時間排序：每個遠端動作佔一行，顯示其相對於配置文件的開始時間、持續時間，以及一個分為排隊、輸入擷取、執行和輸出上傳時間的條形圖，比例係根據頁面上最長的動作調整。將鼠標懸停在條形圖上可查看每個階段的持續時間。該表格使用已上傳的 Bazel 配置文件，並將服務器階段僅與同一配置文件線程中明確無誤的動作關聯。

缺少計時數據表示**未記錄**，而非零。較舊的配置文件、缺失的動作間隔以及被 Bazel 省略的短階段可能會導致表格為空，即使確實發生了遠端工作。記錄的重試會在每個動作內累計。服務器元數據可能描述的是快取結果，因此這些計時數據既不能證明是全新執行，也不屬於可計費用量。客戶端輸入上傳和本地執行輸出的上傳不包含在輸出上傳時間內。

相同數據可通過構建步驟 REST 端點配合 `remote_execution=true` 以及 `list_bazel_build_steps` / `get_bazel_build_step` MCP 工具取得。計時數據會隨配置文件步驟保留 90 日。

### 檢查遠端動作 {#inspect-a-remote-action}

當 Tuist 的執行器記錄一個動作時，其在叫用的**遠端執行**分頁中的行會鏈接到該動作的頁面。**概覽**顯示狀態和退出代碼、排隊、輸入擷取、執行和輸出上傳時間，動作是否被調度或在為該叫用租賃的工作節點上運行，以及工作節點、內存、超時和動作摘要。失敗的動作還會顯示一個**錯誤**卡片：按其標準錯誤中識別出的編譯器錯誤（Clang、GCC、Swift、javac、Go 和 rustc 格式）按文件分組，或者在無法識別時顯示其退出代碼和標準錯誤的結尾。**日誌**在一個帶有行號的日誌中顯示標準輸出後跟標準錯誤，並高亮顯示錯誤行。類似 CI 作業日誌，它會打開在末尾，而**載入更早的行**則可以向後翻頁。記錄會保留每個流的前 16 KiB；執行器還會將更長的流完整存儲為運行工件，因此日誌和**錯誤**卡片涵蓋所有輸出。超過 16 MiB 的流僅保留其前 16 KiB 和最後 16 MiB。日誌中的標記會顯示字節缺失的位置及原因：從非常長的流中跳過，或未存儲，例如副本已過期。**概覽**上的**命令**卡片顯示命令行（可通過**複製**複製）、工作目錄和輸出路徑，以及在摺疊部分中的環境和平台屬性。

名稱包含 `TOKEN`、`SECRET`、`PASSWORD` 或 `KEY` 的環境變量，以及以此方式命名的標誌的值，均顯示為 `****`。記錄僅供參考：沒有鏈接的行意味著沒有記錄能明確匹配其輸出，並不表示動作在本地運行。記錄會保留 90 日。REST 端點 `GET /api/projects/{account_handle}/{project_handle}/bazel/invocations/{invocation_id}/remote-actions` 和 `.../remote-actions/{operation_id}` 以及 `list_bazel_remote_actions` / `get_bazel_remote_action` MCP 工具返回相同的記錄；`.../remote-actions/{operation_id}/logs/{stdout|stderr}` 和 `get_bazel_remote_action_log` 則按字節範圍讀取日誌。存儲的日誌副本屬於運行工件，並會隨計劃的運行工件窗口過期。

## 構建洞察 {#build-insights}

默認情況下，`tuist bazel setup` 也會配置 Bazel 的 Build Event Service，以便已完成的命令出現在 **叫用** 儀表板上。請參閱 <.localized_link href="/guides/features/build-insights/bazel">Bazel 構建洞察</.localized_link> 了解儀表板顯示的內容以及如何附加自定義元數據。

如果你只想使用遠端快取而不希望發送構建事件流，可以選擇退出：

```bash
tuist bazel setup --no-build-insights
```

## 持續集成 {#continuous-integration}

使用 <.localized_link href="/guides/server/authentication#continuous-integration">身份驗證指南</.localized_link> 中的一種方法對 CI 進行身份驗證，然後作為 checkout 步驟的一部分運行一次 `tuist bazel setup`，以便 `.bazelrc.tuist` 反映運行器的正確區域。請參閱 <.localized_link href="/guides/integrations/continuous-integration">持續集成指南</.localized_link> 獲取針對特定提供商的示例。

## 數據保留 {#data-retention}

Tuist 會將遠端快取觀察數據保留 90 日。請參閱 <.localized_link href="/guides/server/data-retention">數據保留</.localized_link> 了解完整政策。
