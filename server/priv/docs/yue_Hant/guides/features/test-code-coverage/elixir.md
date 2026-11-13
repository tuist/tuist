---
{
  "title": "Elixir 代碼覆蓋率",
  "titleTemplate": ":title · 代碼覆蓋率 · 功能 · 指南 · Tuist",
  "description": "使用 mix test --cover 上傳 Elixir 專案的行覆蓋率，並按檔案、應用程式及提交記錄追蹤。"
}
---
# Elixir 程式碼覆蓋率 {#elixir-code-coverage}

程式碼覆蓋率會告訴你測試執行了你程式碼中的哪些行。Hex 套件會上傳每次 `mix test --cover` 執行的行覆蓋率，而 Tuist 會將一個 commit 的所有執行合併為單一數值，涵蓋整個專案、每個 OTP 應用程式以及每個檔案。儀表板的 **程式碼覆蓋率** 頁面會顯示每個 commit 的數據，以及每個分支的趨勢。

> [!IMPORTANT]
> **必要條件**
>
> - 完成 <.localized_link href="/guides/get-started/elixir-project">共用 Elixir 設定</.localized_link>，此設定會透過套件路由 `mix test`

## 設定 {#setup}

### 執行帶有覆蓋率的測試 {#run-your-tests}

傳遞 `--cover`，就像你在沒有 Tuist 的情況下對 `mix test` 所做的那樣：

```sh
mix test --cover
```

套件會上傳覆蓋率以及該次執行的測試結果。當測試套件完成時，它也會執行與 Mix 覆蓋率工具相同的操作，並使用相同的 `test_coverage` 選項進行設定：

- **摘要。** 它會列印每個模組及總體的覆蓋率。`summary: false` 會將其關閉。
- **閾值。** 當總體覆蓋率低於閾值時，執行會以退出狀態 3 失敗；除非你另行設定，否則閾值為 90%：

```elixir
def project do
  [
    test_coverage: [summary: [threshold: 80]]
  ]
end
```

如同在 Mix 中，閾值屬於摘要的一部分，因此 `summary: false` 會同時關閉兩者。若要在不導致執行失敗的情況下列印摘要，請設定 `threshold: 0`。列在 `test_coverage: [ignore_modules: [...]]` 中的模組會被排除在摘要和上傳之外。

Tuist 會追蹤每個 commit 的覆蓋率，因此你的專案需要位於 Git 儲存庫中：在非 Git 儲存庫環境下的執行會上傳其測試結果，但不會上傳覆蓋率。

覆蓋率依賴套件上傳的 <.localized_link href="/guides/features/test-insights/elixir#git-history">Git 歷史記錄</.localized_link>，這能將 commit 放置在其分支上。持續整合上的執行始終會上傳它，而 `--cover` 執行則會在任何機器上上傳它。使用 `--cover` 時，套件還會找出 pull request 的分叉點：它會獲取基礎分支並根據需要加深淺層克隆。在持續整合上，淺層檢出也會在不包含檔案內容的情況下加深，直到達到 Tuist 已拥有的 commit，確保不會上傳缺少父 commit 的 commit。設定 `TUIST_GIT_UNSHALLOW_ENABLED=false` 以防止其聯繫遠端。

### 分片執行 {#sharded-runs}

當你 <.localized_link href="/guides/features/test-sharding/elixir">分片你的測試</.localized_link> 時，請使用 `--cover` 執行每個分片：

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix tuist.test --cover
```

在新的 runner 上，使用分片指南中 <.localized_link href="/guides/features/test-sharding/elixir#test-phase">測試階段</.localized_link> 的 bootstrap 命令，這可以防止 Mix 在分片下載其構建之前編譯每個依賴項，並向其添加 `--cover`。

分片僅報告其自身的覆蓋率且不檢查閾值，因為它只運行了套件的一部分。Tuist 會將一次執行的所有分片合併為單一數值。

每個分片會將覆蓋率計數器添加到其下載的構建中。若要改為只執行一次，請也將 `--cover` 傳遞給構建階段：

```sh
MIX_ENV=test mix tuist.test.build --shard-max 5 --cover
```

當你在 pipeline 執行之間保留構建目錄，並在不收集覆蓋率的執行中重用該目錄時，請不要使用此選項，以便該構建保持無計數器狀態。

### 在 CI 上完成每個 commit {#complete-each-commit}

一個 commit 的覆蓋率通常來自多個 job：每個分片、每個資料庫版本或每個應用程式各一個。Tuist 無法判斷最後一個是否已報告，因此你需要告訴它。當一個 commit 的所有測試 job 完成後，在依賴於所有這些 job 的 job 中執行以下命令：

```sh
MIX_ENV=test mix tuist.coverage.complete
```

該任務從 `GIT_COMMIT` 或檢出的 `HEAD` 讀取 commit；傳遞 `--commit <sha>` 以指定另一個 commit。在 commit 完成之前，其覆蓋率會顯示為 **進行中**，且不會包含在其分支的趨勢中。

## 運作方式 {#how-it-works}

### 原生行計數器 {#native-line-counters}

Mix 的覆蓋率工具會在每次執行開始時為 Erlang 的 `cover` 重新編譯每個模組，這在大型專案上會變慢。該套件改為使用運行時的原生行計數器進行計數。它僅重新編譯自上次執行以來由編譯寫入的模組，將運行時切換到這些計數器，並在套件完成時讀取它們。Mix 的覆蓋率工具被排除在外，但其摘要和閾值得以保留。

該套件會在以下情況回退到 Mix 的覆蓋率工具，並進行相同的上傳：

- umbrella 專案的根目錄。在每個應用程式內部運行測試以進行原生計數。
- 設定了自身 `test_coverage: [tool: ...]` 的專案。
- 沒有 JIT 的運行時，無法進行原生計數。

### Tuist 測量什麼 {#what-tuist-measures}

- **應用程式。** 每個 OTP 應用程式都是儀表板上的一個目標，擁有自己的覆蓋率。
- **僅產品程式碼。** 測試路徑下的檔案屬於測試程式碼。Tuist 會儲存它們，但將它們排除在所有數值之外。
- **每檔案行數。** 無論一行屬於多少個模組，它在每個檔案中只計數一次。
- **函式。** 每一行都歸屬於其上方最近的子句所屬的函式。由編譯器或宏生成的函式（例如 `__info__/1` 或 `__schema__/1`）不會列出，但它們的行仍會計入其檔案。

因此，Tuist 的數值與 Mix 自身的覆蓋率報告在幾個方面有所不同：它們排除了測試程式碼，並按檔案而非按模組計算行數。原生計數還能看到應用程式啟動時運行的程式碼，並排除編譯器證明永遠不會運行的行，而 Mix 的工具會將這些行報告為從未覆蓋。

### 跳過的測試 {#skipped-tests}

Tuist 無法延續被執行跳過的測試的覆蓋率：套件記錄的是整個執行所執行的內容，而非每個測試執行的內容。因此，當執行的參數通過 `--only`、`--exclude`、`--failed`、`--stale`、`--name-pattern`、`--max-failures` 或測試檔案或行來排除測試時，該 commit 的覆蓋率會顯示為 **不完整**，除非也運行了一個未排除任何內容的同變體執行。兩個各自排除測試的執行（例如 `--exclude slow` 和 `--only slow`）仍會使 commit 變得不完整，即使它們合起來運行了所有測試。

某些測試是故意被排除的，不會導致 commit 不完整：

- **你的測試助手的排除項。** `ExUnit.start(exclude: [...])` 預設排除的測試是你的專案對於其套件預設運行內容的選擇，因此 Tuist 不會將它們視為缺失。在另一個 job 中使用 `--include` 或 `--only` 運行它們，以將其覆蓋率添加到 commit 中。
- **在程式碼中跳過的測試**，使用 `@tag :skip`。
- **<.localized_link href="/guides/features/test-insights/flaky-tests/elixir#quarantining">隔離</.localized_link>跳過的測試。** 它們被排除在外，如同已被移除，因此僅由它們覆蓋的行會被計為未覆蓋。

### 完整和不完整的 commits {#commit-status}

儀表板上的每個 commit 都有一個狀態：

| 狀態 | 含義 |
| --- | --- |
| 進行中 | 已有執行回報覆蓋率，但該 commit 尚未運行 `mix tuist.coverage.complete`。 |
| 完整 | 該 commit 的所有執行的每個測試都已運行，或是被故意排除。 |
| 不完整 | 部分覆蓋率無法確定，因此該數值為下限。 |
| 未測量 | 沒有執行回報該 commit 的覆蓋率。 |

分支的趨勢僅包含完整的 commits。例如，當出現以下情況時，commit 會不完整：

- 變體的每次執行都以其自身參數排除了測試。
- 變體的每次執行都缺少部分 shard。
- 變體的覆蓋率僅來自於具有未提交變更的 checkout 上的 CI 執行。

變體是你通過 `--scheme` 傳遞的標籤，例如資料庫版本。沒有標籤的執行屬於同一個變體。Commit 的數值合併了所有執行，但 Tuist 會獨立檢查每個變體的完整性，因此每個變體都需要一個未排除任何內容的執行。

## 效能影響 {#performance-impact}

收集覆蓋率會增加額外開銷，因此帶有 `--cover` 的執行比不帶它的執行耗時更長。第一次執行會使用行計數器重新編譯你的模組；後續執行僅重新編譯變更的部分，因此開銷大幅降低。在大型專案中，原生計數也比 Mix 的覆蓋率工具快得多。

## 限制 {#limitations}

- **無 HTML 報告。** 原生計數不會向 `test_coverage: [output: ...]` 目錄寫入報告，且當設定該目錄時執行會發出警告。儀表板的檔案頁面會改為顯示已覆蓋的行。
- **重試不會增加覆蓋率。** 使用<.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">測試重試</.localized_link>時，覆蓋率來自第一次嘗試。該次嘗試已運行了失敗的測試，因此缺失的行僅限於那些在不穩定測試的重試中能到達、但在第一次嘗試中未能到達的行。
- **來自 fork 的 pull request 無覆蓋率。** 只有通過 Tuist 驗證的執行才會上傳覆蓋率，而 CI 通常會對來自 fork 的 pull request 隱藏密鑰和身份令牌，因此這些執行不會回報覆蓋率。一旦合併，該 commit 將在你的分支上使用憑證運行，並照常回報其覆蓋率。

## 查詢覆蓋率 {#querying}

儀表板的**程式碼覆蓋率**頁面顯示每個 commit 的數值、其應用程式及其檔案，以及每次執行覆蓋的行。代理也可以通過<.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol 伺服器</.localized_link>獲取相同的數據。
