---
{
  "title": "Bazel 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 喺團隊同 CI 之間共用 Bazel 遠端快取項目。"
}
---
# Bazel 快取 {#bazel-cache}

Tuist 提供一個 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 快取，Bazel 可以將其作為遠端快取連接。當某個動作的輸出已存在於快取中時，Bazel 會跳過該動作並從 Tuist 的快取中提取結果，從而節省團隊和 CI 環境中的編譯時間。如需 GitHub Actions 設定，請參閱 [Bazel on GitHub Actions](https://tuist.dev/solutions/bazel-github-actions)。如需了解遠端快取的工作原理，以及自託管快取與受管快取的比較，請參閱 [Bazel remote cache](https://tuist.dev/solutions/bazel-remote-cache)。

## 設定 {#setup}

在 Bazel 工作區的根目錄下執行：

```bash
tuist bazel setup
```

這會在你的 `.bazelrc` 旁邊寫入一個 `.bazelrc.tuist` 檔案，連接到最近的 Tuist 快取區域，並透過每個工作區的憑證輔助工具進行驗證。它還會在你的儲存庫的 `.bazelrc` 中加入一行 `try-import`：

```text
try-import %workspace%/.bazelrc.tuist
```

如果你想自行管理匯入，請傳遞 `--no-add-bazelrc-import`。

將 `.bazelrc.tuist` 加入你的 `.gitignore`，並在每台機器上執行設定，而不是將其提交。生成的檔案指向當前用戶 Tuist 配置目錄下的絕對憑證輔助工具路徑，以及最接近生成該檔案的機器的快取區域，因此這兩個值都不會轉移給隊友或持續整合執行器。請在 `.bazelrc` 中提交 `try-import` 行，因為它在每台機器上都相同。

當找不到 Bazel 工作區標記、檔案是符號連結，或已配置遠端快取或 Build Event Service 時，設定會保留現有的 `.bazelrc` 不變。這樣一來，再次執行它就是冪等的。

執行正常的 Bazel 命令以驗證整合：

```bash
bazel build //...
```

快取活動隨後會出現在 Tuist 儀表板中專案的 **Bazel Cache** 頁面上，該頁面顯示快取傳輸、下載和上傳、讀寫延遲、吞吐量以及動作快取命中率。專案 **Overview** 會提供相同的動作快取命中率摘要，並附上構建持續時間。

若要查看某個命令如何使用快取，請從 **Invocations** 開啟它。調用頁面將動作快取查找與內容物件請求分開，因此你可以區分冷動作快取與緩慢的構件下載。

## 遠端執行 {#remote-execution}

Tuist 還可以在其 Linux 執行器上運行你的 Bazel 動作，因此快取未命中會在遠端運行，而不是在本地機器或 CI 執行器上運行。遠端執行適用於已啟用的帳戶；請 [email us](mailto:contact@tuist.dev) 或 [book a call](https://cal.tuist.dev/team/tuist/tuist) 以為你的帳戶啟用。然後將 `--remote-execution` 傳遞給設定：

```bash
tuist bazel setup --remote-execution
```

設定隨後會在 `.bazelrc.tuist` 中將 Bazel 指向 Tuist 的執行器，位於遠端快取旁邊。它每次運行時都會查找當前執行器和映像，因此請重新運行設定，而不是複製生成的值。動作使用執行器的 Linux 工具鏈運行，而不是你機器上安裝的工具，因此請在工作區中聲明你的動作所需的工具鏈。

設定還會將 `--jobs` 設置為你的帳戶一次可以運行的遠端動作數量的兩倍，以便每個動作都有下一個動作等待。否則，Bazel 會並行運行與機器核心數量一樣多的動作，而 2 核心的 CI 執行器只會保持兩個遠端動作處於飛行狀態。

若要使用不同的值，請在命令行上傳遞 `--jobs`，或在 `try-import` 行之後的 `.bazelrc` 中設置它。Bazel 使用它讀取的最後一個值，因此該行之前的 `--jobs` 會被生成的值替換。

### 執行器大小 {#executor-sizes}

動作預設使用 4 GB 記憶體和 2 個 vCPU。設置 `tuist-memory-gb` 執行屬性以請求更大的 VM：

| `tuist-memory-gb` | 記憶體 | vCPU | 工作區磁碟 |
| --- | --- | --- | --- |
| `4`（預設） | 4 GB | 2 | 30 GB |
| `8` | 8 GB | 4 | 30 GB |
| `16` | 16 GB | 8 | 30 GB |

例如，在 `.bazelrc` 的 `try-import` 行**之後**加入以下設定，以預設請求 8 GB：

```text
build --remote_default_exec_properties=tuist-memory-gb=8
```

針對單一目標，請在其 Bazel 規則中改用 `exec_properties = {"tuist-memory-gb": "8"}`。僅支援 `4`、`8` 和 `16`。較大的動作會按比例消耗更多帳戶分配的 vCPU 和記憶體限額，從而減少可同時執行的數量。規格必須同時符合這兩項限制。生成的 `--jobs` 使用預設規格；如需請求較大規格，請視需要覆寫它。

執行器目前使用 Tuist 的 Linux amd64 映像檔。無法透過 setup 設定任意容器映像檔、其他執行作業系統與架構、持久性動作工作節點，或自備執行器。請重新執行 setup 以取得目前的映像檔和端點。

### 遠端動作時間 {#remote-action-timings}

開啟專案側邊欄中的**Remote execution**，查看包含已記錄遠端階段的叫用和動作、平均及 p50/p90/p99 佇列與執行時間（連同相較上一週期的變化）、趨勢圖表，以及每個叫用的階段時間連結。可按環境（CI 或本機）和日期（最多 90 天）篩選。叫用表格顯示每個叫用的平均、p50 和 p90 執行時間。可依指令、目標或叫用 ID 搜尋，並按狀態、指令、目標或遠端動作數量篩選，以及除「Invocation」外的任何欄位排序。搜尋和表格篩選僅適用於叫用表格，不適用於分析數據。

開啟叫用的**Remote execution**分頁，查看其遠端動作，可按持續時間（最長優先）或開始時間排序：每個遠端動作佔一行，顯示其相對於剖析檔的開始時間、持續時間，以及拆分為佇列、輸入抓取、執行和輸出上傳時間的長條圖（按頁面中最長動作縮放）。將滑鼠懸停在長條上可查看每個階段的持續時間。該表格使用已上傳的 Bazel 剖析檔，並將伺服器階段僅關聯到同一剖析檔執行緒中明確無歧義的動作。

缺少時間數據表示**Not recorded**，而非零。較舊的剖析檔、缺少的動作間隔，以及被 Bazel 省略的短階段，可能導致即使發生遠端工作，表格仍為空白。記錄的重試會在每個動作內合計。伺服器中繼資料可能描述快取結果，因此這些時間數據既非新鮮執行的證明，亦非計費用量。客戶端輸入上傳和本機執行輸出的上傳不計入輸出上傳時間。

相同數據可透過建置步驟 REST 端點取得，需搭配 `remote_execution=true` 以及 `list_bazel_build_steps` / `get_bazel_build_step` MCP 工具。時間數據會隨剖析檔步驟保留 90 天。

## 建置洞察 {#build-insights}

預設情況下，`tuist bazel setup` 也會設定 Bazel 的 Build Event Service，讓已完成的指令顯示在 **Invocations** 儀表板上。請參閱 <.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link>，了解儀表板顯示的內容以及如何附加自訂中繼資料。

如果你只想要遠端快取，而不想傳送建置事件串流，可以使用以下指令退出：

```bash
tuist bazel setup --no-build-insights
```

## 持續整合 {#continuous-integration}

使用 <.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link> 中的其中一種方法為 CI 進行驗證，然後在 checkout 步驟中執行一次 `tuist bazel setup`，以便 `.bazelrc.tuist` 反映執行器所屬的正確區域。請參閱 <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link> 以取得針對不同供應商的範例。

## 數據保留 {#data-retention}

Tuist 會保留遠端快取觀察數據 90 天。請參閱 <.localized_link href="/guides/server/data-retention">data retention</.localized_link> 以了解完整政策。
