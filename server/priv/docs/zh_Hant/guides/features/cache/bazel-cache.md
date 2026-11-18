---
{
  "title": "Bazel 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist，在團隊與 CI 之間共享 Bazel 遠端快取項目。"
}
---
# Bazel 快取 {#bazel-cache}

Tuist 提供一個 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 快取，Bazel 可將其連接為遠端快取。當動作的輸出已存在於快取中時，Bazel 會跳過該動作並從 Tuist 的快取中提取結果，為你的團隊與 CI 環境節省編譯時間。如需 GitHub Actions 設定，請參閱 [Bazel on GitHub Actions](https://tuist.dev/solutions/bazel-github-actions)。如需了解遠端快取的運作方式，以及自託管與受管快取的比較，請參閱 [Bazel remote cache](https://tuist.dev/solutions/bazel-remote-cache)。

## 設定 {#setup}

在 Bazel 工作區的根目錄執行：

```bash
tuist bazel setup
```

這會在你的 `.bazelrc` 旁邊寫入一個 `.bazelrc.tuist` 檔案，連線至最近的 Tuist 快取區域，並透過每個工作區專屬的憑證輔助工具進行驗證。它也會在你的儲存庫的 `.bazelrc` 中加入一行 `try-import`：

```text
try-import %workspace%/.bazelrc.tuist
```

如果你想自行管理匯入，請傳入 `--no-add-bazelrc-import`。

將 `.bazelrc.tuist` 加入你的 `.gitignore`，並在每台機器上執行設定，而不是將其提交到版本控制。產生的檔案會指向目前使用者的 Tuist 設定目錄下的絕對憑證輔助工具路徑，以及最接近產生該檔案之機器的快取區域，因此這些值不會轉移給隊友或持續整合執行器。請在 `.bazelrc` 中提交 `try-import` 這一行，因為它在每台機器上都相同。

當找不到 Bazel 工作區標記、檔案是符號連結，或已設定遠端快取或 Build Event Service 時，設定會保留現有的 `.bazelrc` 不變。這樣一來，再次執行設定就是冪等的。

執行一般的 Bazel 指令來驗證整合：

```bash
bazel build //...
```

快取活動隨後會出現在 Tuist 儀表板中專案的 **Bazel Cache** 頁面，顯示快取傳輸、下載與上傳、讀取與寫入延遲、吞吐量，以及動作快取命中率。專案 **Overview** 會提供相同的動作快取命中率摘要，並與建置持續時間並列顯示。

若要查看單一指令如何使用快取，請從 **Invocations** 開啟它。叫用頁面會將動作快取查詢與內容物件請求分開，讓你能夠分辨冷動作快取與緩慢的構件下載。

## 遠端執行 {#remote-execution}

Tuist 也能在其 Linux 執行器上執行你的 Bazel 動作，因此快取未命中會在遠端執行，而非在本機機器或 CI 執行器上執行。已啟用的帳戶可使用遠端執行功能；請 [email us](mailto:contact@tuist.dev) 或 [book a call](https://cal.tuist.dev/team/tuist/tuist) 以為你的帳戶啟用。然後在設定時傳入 `--remote-execution`：

```bash
tuist bazel setup --remote-execution
```

設定隨後會在 `.bazelrc.tuist` 中將 Bazel 指向 Tuist 的執行器，位於遠端快取旁邊。每次執行時都會查找目前的執行器與映像檔，因此請重新執行設定，而不是複製產生的值。動作使用執行器的 Linux 工具鏈執行，而非你機器上安裝的工具，因此請在工作區中宣告動作所需的工具鏈。

設定也會將 `--jobs` 設為你的帳戶一次能執行的遠端動作數量的兩倍，讓每個動作都有下一個動作等待執行。若沒有此設定，Bazel 會平行執行與機器核心數相同數量的動作，而雙核心 CI 執行器只會同時保持兩個遠端動作處於進行中。

若要使用不同的值，請在命令列上傳入 `--jobs`，或在 `try-import` 行之後的 `.bazelrc` 中設定。Bazel 會使用最後讀取到的值，因此該行之前的 `--jobs` 會被產生的值取代。

### 執行器規格 {#executor-sizes}

動作預設使用 4 GB 記憶體與 2 個 vCPU。設定 `tuist-memory-gb` 執行屬性以請求更大的 VM：

| `tuist-memory-gb` | 記憶體 | vCPU | 工作區磁碟 |
| --- | --- | --- | --- |
| `4`（預設） | 4 GB | 2 | 30 GB |
| `8` | 8 GB | 4 | 30 GB |
| `16` | 16 GB | 8 | 30 GB |

例如，在 `.bazelrc` 中的 `try-import` 行**之後**加入此行，以預設請求 8 GB：

```text
build --remote_default_exec_properties=tuist-memory-gb=8
```

針對單一目標，請在其 Bazel 規則中使用 `exec_properties = {"tuist-memory-gb": "8"}`。僅支援 `4`、`8` 與 `16`。較大的動作會按比例消耗更多帳戶分配的 vCPU 與記憶體限制，減少可同時執行的數量。規格必須同時符合這兩項限制。產生的 `--jobs` 使用預設規格；若請求較大規格，請視需要覆寫它。

執行器目前使用 Tuist 的 Linux amd64 映像檔。任意容器映像檔、其他執行作業系統與架構、持久化動作工作節點，以及自帶執行器，無法透過設定進行配置。請重新執行設定以取得目前的映像檔與端點。

### 遠端動作計時 {#remote-action-timings}

在專案側邊欄中開啟 **Remote execution**，查看具有記錄遠端階段的叫用與動作、平均與 p50/p90/p99 佇列與執行時間（含與前一週期的變化）、趨勢圖表，以及每個叫用階段計時的連結。依環境（CI 或本機）與日期（最多 90 天）篩選。叫用表格顯示每個叫用的平均、p50 與 p90 執行時間。可依指令、目標或叫用 ID 搜尋，依狀態、指令、目標或遠端動作數量篩選，並依除「Invocation」外的任何欄位排序。搜尋與表格篩選僅適用於叫用表格，不適用於分析資料。

開啟叫用的 **Remote execution** 標籤頁以查看其遠端動作，依持續時間（最長優先）或開始時間排序：每個遠端動作一列，顯示相對於剖析檔的開始時間、持續時間，以及分為佇列、輸入擷取、執行與輸出上傳時間的長條圖，並按頁面上最長的動作縮放。將滑鼠懸停在長條上可查看每個階段的持續時間。表格使用上傳的 Bazel 剖析檔，並將伺服器階段僅與同一剖析執行緒上明確無誤的動作關聯。

缺少計時表示 **Not recorded**，而非零。較舊的剖析檔、缺少的動作間隔，以及被 Bazel 省略的短暫階段，可能導致表格為空，即使遠端工作確實發生。記錄的重試會在每個動作內加總。伺服器中繼資料可能描述快取結果，因此這些計時既非新鮮執行的證明，也非可計費的使用量。客戶端輸入上傳與本機執行輸出的上傳不包含在輸出上傳時間內。

相同的資料可透過包含 `remote_execution=true` 的建置步驟 REST 端點，以及 `list_bazel_build_steps` / `get_bazel_build_step` MCP 工具取得。計時資料會與剖析步驟一起保留 90 天。

## 建置洞察 {#build-insights}

預設情況下，`tuist bazel setup` 也會設定 Bazel 的 Build Event Service，讓已完成的指令顯示在 **Invocations** 儀表板上。請參閱 <.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link>，了解儀表板顯示的內容以及如何附加自訂中繼資料。

如果您只想要遠端快取，而不想傳送建置事件串流，請使用以下選項退出：

```bash
tuist bazel setup --no-build-insights
```

## 持續整合 {#continuous-integration}

請使用 <.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link> 中的其中一種方法驗證 CI，然後在 checkout 步驟中執行一次 `tuist bazel setup`，以便 `.bazelrc.tuist` 反映執行器的正確區域。請參閱 <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link>，取得針對特定供應商的範例。

## 資料保留 {#data-retention}

Tuist 會將遠端快取觀察資料保留 90 天。請參閱 <.localized_link href="/guides/server/data-retention">data retention</.localized_link> 以了解完整政策。
