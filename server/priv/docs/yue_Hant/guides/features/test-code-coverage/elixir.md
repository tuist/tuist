---
{
  "title": "Elixir 程式碼覆蓋率",
  "titleTemplate": ":title · Code Coverage · Features · Guides · Tuist",
  "description": "使用 mix test --cover 上傳 Elixir 專案的行覆蓋率，並按檔案、應用程式及提交記錄追蹤。"
}
---
# Elixir 代碼覆蓋率 {#elixir-code-coverage}

代碼覆蓋率會告訴你測試執行了你代碼中的哪些行。Hex 套件會上傳每次 `mix test --cover` 運行的行覆蓋率，而 Tuist 會將一個 commit 的多次運行合併為單一數值，涵蓋整個專案、每個 OTP 應用程式以及每個檔案。儀表板的 **代碼覆蓋率** 頁面會顯示每個 commit 的數據，以及每個分支的趨勢。

> [!IMPORTANT]
> **必要條件**
>
> - 完成 <.localized_link href="/guides/get-started/elixir-project">共享 Elixir 設定</.localized_link>，這會讓 `mix test` 透過套件進行路由

## 設定 {#setup}

### 運行帶有覆蓋率的測試 {#run-your-tests}

傳遞 `--cover`，就像你在沒有 Tuist 的情況下對 `mix test` 所做的那樣：

```sh
mix test --cover
```

套件會上傳覆蓋率以及該次運行的測試結果。當測試套件完成時，它也會執行 Mix 覆蓋率工具的功能，並使用相同的 `test_coverage` 選項進行設定：

- **摘要。** 它會列印每個模組及總體的覆蓋率。`summary: false` 會將其關閉。
- **閾值。** 當總體覆蓋率低於閾值時，運行會以退出狀態 3 失敗；除非你另行設定，否則閾值為 90%：

```elixir
def project do
  [
    test_coverage: [summary: [threshold: 80]]
  ]
end
```

與 Mix 一樣，閾值屬於摘要的一部分，因此 `summary: false` 會同時關閉兩者。若要列印摘要但不讓運行失敗，請設定 `threshold: 0`。列在 `test_coverage: [ignore_modules: [...]]` 中的模組不會包含在摘要和上傳內容中。

Tuist 會追蹤每個 commit 的覆蓋率，因此你的專案需要位於 Git 儲存庫中：在非 Git 環境下的運行會上傳測試結果，但不會上傳覆蓋率。

覆蓋率依賴套件上傳的 <.localized_link href="/guides/features/test-insights/elixir#git-history">Git 歷史記錄</.localized_link>，這能將 commit 放置在其分支上。持續整合上的運行始終會上傳它，而 `--cover` 運行則會在任何機器上上傳它。使用 `--cover` 時，套件還會找出 pull request 的分支點：它會獲取基礎分支並根据需要加深淺層克隆。在持續整合中，淺層檢出也會在不包含檔案內容的情況下加深，直到達到 Tuist 已拥有的 commit，確保每個 commit 上傳時都包含其父 commit。設定 `TUIST_GIT_UNSHALLOW_ENABLED=false` 以防止其聯繫遠端。

### 分片運行 {#sharded-runs}

當你 <.localized_link href="/guides/features/test-sharding/elixir">分片測試</.localized_link> 時，請使用 `--cover` 運行每個分片：

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix tuist.test --cover
```

在新的 runner 上，使用分片指南中 <.localized_link href="/guides/features/test-sharding/elixir#test-phase">測試階段</.localized_link> 的 bootstrap 命令，這可以防止 Mix 在分片下載其構建之前編譯所有依賴項，並向其添加 `--cover`。

分片僅報告其自身的覆蓋率且不檢查閾值，因為它只運行了測試套件的一部分。Tuist 會將一次運行的各個分片合併為單一數值。

每個分片會將覆蓋率計數器添加到其下載的構建中。若只想執行一次，請也將 `--cover` 傳遞給構建階段：

```sh
MIX_ENV=test mix tuist.test.build --shard-max 5 --cover
```

當你在管道運行之間保留構建目錄，並在未收集覆蓋率的運行中重用該目錄時，請關閉此選項，以便該構建保持沒有計數器的狀態。

### 在 CI 上完成每個 commit {#complete-each-commit}

一個 commit 的覆蓋率通常來自多個作業：每個分片、每個資料庫版本或每個應用程式各一個。Tuist 無法判斷最後一個作業何時已報告，因此你需要告訴它。當一個 commit 的所有測試作業完成後，在依賴於所有這些作業的作業中運行以下命令：

```sh
MIX_ENV=test mix tuist.coverage.complete
```

任務會從 `GIT_COMMIT` 或檢出的 `HEAD` 讀取 commit；傳遞 `--commit <sha>` 以指定另一個 commit。在 commit 完成之前，其覆蓋率會顯示為 **進行中**，且不會包含在其分支的趨勢中。

## 運作原理 {#how-it-works}

### 原生行計數器 {#native-line-counters}

Mix 的覆蓋率工具會在每次運行開始時為 Erlang 的 `cover` 重新編譯每個模組，這在大型專案中會變慢。該套件改用運行時的原生行計數器進行計數。它僅重新編譯自上次運行以來由編譯寫入的模組，將運行時切換到這些計數器，並在測試套件完成時讀取它們。Mix 的覆蓋率工具被排除在外，但其摘要和閾值得以保留。

對於以下情況，套件會回退到 Mix 的覆蓋率工具，並進行同樣的上傳：

- 傘狀專案的根目錄。在每個應用程式內部運行測試以進行原生計數。
- 設定了自身 `test_coverage: [tool: ...]` 的專案。
- 沒有 JIT 的運行時，無法進行原生計數。

### Tuist 測量什麼 {#what-tuist-measures}

- **應用程式。** 每個 OTP 應用程式都是儀表板上的一個目標，擁有各自的覆蓋率。
- **僅產品代碼。** 測試路徑下的檔案屬於測試代碼。Tuist 會儲存它們，但將它們排除在所有數值之外。
- **每檔案行數。** 無論一行屬於多少個模組，在每個檔案中只計數一次。
- **函數。** 每一行都歸屬於其上方最近的子句所屬的函數。編譯器或宏生成的函數（例如 `__info__/1` 或 `__schema__/1`）不會列出，但它們的行仍會計入其所屬檔案。
- **模板。** 使用原生計數時，編譯進模組的模板（例如 LiveView 的 `.html.heex`、`embed_templates` 或 `EEx.function_from_file`）會作為獨立檔案進行測量，擁有各自的行且無函數。Mix 的覆蓋率工具不測量模板，因此摘要和閾值會將其排除。

因此，Tuist 的數值與 Mix 自身的覆蓋率報告有幾處不同：它們排除了測試代碼，並按檔案而非按模組計數行數。原生計數還能看到應用程式啟動時運行的代碼，並排除編譯器證明永遠不會運行的行，而 Mix 的工具則將這些行報告為從未覆蓋。

### 跳過的測試 {#skipped-tests}

Tuist 無法延續運行中遺漏的測試的覆蓋率：套件記錄的是整個運行情況，而非每個測試的執行情況。因此，當運行的參數遺漏了測試（使用 `--only`、`--exclude`、`--failed`、`--stale`、`--name-pattern`、`--max-failures`，或測試檔案或行）時，該 commit 的覆蓋率會顯示為 **不完整**，除非也運行了同一變體且未遺漏任何內容的運行。兩個各自遺漏測試的運行（例如 `--exclude slow` 和 `--only slow`）仍會使 commit 變得不完整，即使它們合起來運行了所有測試。

有些測試是故意遺漏的，不會導致 commit 不完整：

- **測試助手的排除項。** `ExUnit.start(exclude: [...])` 預設遺漏的測試是你的專案對預設運行套件的選擇，因此 Tuist 不將其視為缺失。在另一個作業中使用 `--include` 或 `--only` 運行它們，以將其覆蓋率添加到 commit 中。
- **代碼中跳過的測試**（使用 `@tag :skip`）。
- **<.localized_link href="/guides/features/test-insights/flaky-tests/elixir#quarantining">隔離</.localized_link>跳過的測試。** 它們被遺漏，如同已被移除，因此僅由它們覆蓋的行會被計為未覆蓋。

### 完整與不完整的 commit {#commit-status}

儀表板上的每個 commit 都有一個狀態：

| 狀態 | 含義 |
| --- | --- |
| 進行中 | 運行已報告覆蓋率，但 `mix tuist.coverage.complete` 尚未針對該 commit 運行。 |
| 完整 | commit 運行的所有測試均已執行，或故意遺漏。 |
| 不完整 | 部分覆蓋率無法確定，因此該數值為下限。 |
| 未測量 | 沒有運行報告該 commit 的覆蓋率。 |

分支趨勢僅包含完整的 commit。當出現以下情況時，commit 會不完整：

- 變體的每次運行都因其自身參數而遺漏了測試。
- 變體的每次運行都缺少部分分片。
- 變體的覆蓋率僅來自於具有未提交更改的檢出上的 CI 運行。

變體是你透過 `--scheme` 傳遞的標籤，例如資料庫版本。沒有標籤的運行屬於同一個變體。commit 的數值會合併所有運行，但 Tuist 會單獨檢查每個變體的完整性，因此每個變體都需要一次不遺漏任何內容的運行。

## 效能影響 {#performance-impact}

收集覆蓋率會增加開銷，因此帶有 `--cover` 的運行比不帶它的運行耗時更長。首次運行會使用行計數器重新編譯你的模組；後續運行僅重新編譯更改的部分，因此成本大幅降低。在大型專案中，原生計數也比 Mix 的覆蓋率工具快得多。

## 限制 {#limitations}

- **無 HTML 報告。** 原生計數不會將報告寫入 `test_coverage: [output: ...]` 目錄，且當設定該目錄時運行會發出警告。儀表板的檔案頁面會改為顯示已覆蓋的行。
- **重試不會增加覆蓋率。** 使用 <.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">測試重試</.localized_link> 時，覆蓋率取決於第一次嘗試。該次嘗試已運行了失敗的測試，因此缺失的行僅限於那些在不穩定測試的重試中能到達、但在首次嘗試中未能到達的行。
- **來自 Fork 的 Pull Request 無覆蓋率。** 只有經過 Tuist 身份驗證的運行才會上傳覆蓋率，而 CI 通常會對來自 Fork 的 Pull Request 隱藏密鑰和身份令牌，因此這些運行不會報告覆蓋率。一旦合併，commit 會在你的分支上使用憑證運行並照常報告其覆蓋率。

## 查詢覆蓋率 {#querying}

儀表板的 **代碼覆蓋率** 頁面顯示每個 commit 的數值、其應用程式及其檔案，以及每次運行覆蓋的行。代理可以透過 <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol 伺服器</.localized_link> 存取相同的數據。
