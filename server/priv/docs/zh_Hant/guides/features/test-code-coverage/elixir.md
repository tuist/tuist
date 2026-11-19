---
{
  "title": "Elixir 程式碼涵蓋率",
  "titleTemplate": ":title · 程式碼涵蓋率 · 功能 · 指南 · Tuist",
  "description": "使用 mix test --cover 上傳 Elixir 專案的程式碼行涵蓋率，並依檔案、應用程式及提交追蹤。"
}
---
# Elixir 程式碼涵蓋率 {#elixir-code-coverage}

程式碼涵蓋率會告訴你測試執行了程式碼中的哪些行。Hex 套件會上傳每次 `mix test --cover` 執行的行涵蓋率，而 Tuist 會將一個 commit 的多次執行合併為單一數值，適用於整個專案、每個 OTP 應用程式以及每個檔案。儀表板的 **程式碼涵蓋率** 頁面會顯示每個 commit 的數值，以及每個分支的趨勢。

> [!IMPORTANT]
> **必要條件**
>
> - 完成 <.localized_link href="/guides/get-started/elixir-project">共用的 Elixir 設定</.localized_link>，此設定會讓 `mix test` 透過套件執行

## 設定 {#setup}

### 執行含涵蓋率的測試 {#run-your-tests}

傳遞 `--cover`，就像在沒有 Tuist 的情況下對 `mix test` 所做的一樣：

```sh
mix test --cover
```

套件會上傳涵蓋率以及該次執行的測試結果。當測試套件完成時，它也會執行與 Mix 涵蓋率工具相同的操作，並使用相同的 `test_coverage` 選項進行設定：

- **摘要。** 它會列印每個模組及總計的涵蓋率。`summary: false` 會關閉此功能。
- **門檻值。** 當總計低於門檻值時，它會讓執行失敗並回傳結束狀態 3；除非你另行設定，否則預設為 90%：

```elixir
def project do
  [
    test_coverage: [summary: [threshold: 80]]
  ]
end
```

如同在 Mix 中，門檻值屬於摘要的一部分，因此 `summary: false` 會同時關閉兩者。若要列印摘要但不讓執行失敗，請設定 `threshold: 0`。列在 `test_coverage: [ignore_modules: [...]]` 中的模組不會包含在摘要和上傳內容中。

Tuist 會追蹤每個 commit 的涵蓋率，因此你的專案必須位於 Git 儲存庫中：在非 Git 儲存庫中執行時，會上傳測試結果，但不會上傳涵蓋率。

涵蓋率依賴套件上傳的 <.localized_link href="/guides/features/test-insights/elixir#git-history">Git 歷史記錄</.localized_link>，這會將 commit 放置在其分支上。持續整合上的執行永遠會上傳它，而 `--cover` 執行則會在任何機器上上傳它。使用 `--cover` 時，套件也會找出拉取請求的分叉點：它會抓取基礎分支，並根據需要深化淺層複製。在持續整合上，淺層檢出也會在不包含檔案內容的情況下深化，直到達到 Tuist 已擁有的 commit，因此絕不會上傳沒有父 commit 的 commit。設定 `TUIST_GIT_UNSHALLOW_ENABLED=false` 可防止其聯絡遠端。

### 分片執行 {#sharded-runs}

當你 <.localized_link href="/guides/features/test-sharding/elixir">對測試進行分片</.localized_link> 時，請使用 `--cover` 執行每個分片：

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix tuist.test --cover
```

在新的執行器上，請使用分片指南中 <.localized_link href="/guides/features/test-sharding/elixir#test-phase">測試階段</.localized_link> 的 bootstrap 指令，這可防止 Mix 在下載分片的建置前編譯每個相依性，並向其添加 `--cover`。

分片僅報告其自身的涵蓋率且不檢查門檻值，因為它只執行套件的一部分。Tuist 會將一次執行的所有分片合併為單一數值。

每個分片會將涵蓋率計數器添加到其下載的建置中。若希望只執行一次，請也將 `--cover` 傳遞給建置階段：

```sh
MIX_ENV=test mix tuist.test.build --shard-max 5 --cover
```

當你在管道執行之間保留建置目錄，並在未收集涵蓋率的執行中重複使用時，請不要使用此選項，以便該建置保持不含計數器的狀態。

### 在 CI 上完成每個 commit {#complete-each-commit}

一個 commit 的涵蓋率通常來自多個工作：每個分片、每個資料庫版本或每個應用程式各一個。Tuist 無法判斷最後一個工作何時已完成報告，因此你需要告訴它。當一個 commit 的所有測試工作完成後，請在依賴所有這些工作的另一個工作中執行以下指令：

```sh
MIX_ENV=test mix tuist.coverage.complete
```

此任務會從 `GIT_COMMIT` 或檢出的 `HEAD` 讀取 commit；傳遞 `--commit <sha>` 以指定另一個 commit。在 commit 完成之前，其涵蓋率會顯示為 **進行中**，且不會納入其分支的趨勢中。

## 運作方式 {#how-it-works}

### 原生行計數器 {#native-line-counters}

Mix 的涵蓋率工具會在每次執行開始時，為 Erlang 的 `cover` 重新編譯每個模組，這在大型專案中會變慢。套件改用執行期的原生行計數器進行計數。它僅重新編譯自上次執行以來由編譯寫入的模組，將執行期切換至這些計數器，並在測試套件完成時讀取它們。Mix 的涵蓋率工具會被略過，但其摘要和門檻值會保留。

套件會在以下情況退回使用 Mix 的涵蓋率工具，並以上傳相同內容：

- 傘狀專案的根目錄。在每個應用程式內執行測試以進行原生計數。
- 自行設定 `test_coverage: [tool: ...]` 的專案。
- 沒有 JIT 的執行期，無法進行原生計數。

### Tuist 測量的內容 {#what-tuist-measures}

- **應用程式。** 每個 OTP 應用程式都是儀表板上的一個目標，擁有各自的涵蓋率。
- **僅產品程式碼。** 位於測試路徑下的檔案屬於測試程式碼。Tuist 會儲存它們，但將其排除在所有數值之外。
- **每檔案的行數。** 無論一行屬於多少個模組，在每個檔案中僅計算一次。
- **函式。** 每一行都屬於其上方最近的子句所屬的函式。編譯器或巨集產生的函式（例如 `__info__/1` 或 `__schema__/1`）不會列出，但它們的行仍會計入其所屬檔案。

因此，Tuist 的數值與 Mix 自身的涵蓋率報告有幾點不同：它們排除了測試程式碼，並按檔案而非按模組計算行數。原生計數也能看到應用程式啟動時執行的程式碼，並排除編譯器證明永遠不會執行的行，而 Mix 的工具會將這些行報告為從未涵蓋。

### 跳過的測試 {#skipped-tests}

Tuist 無法延續被執行略過的測試之涵蓋率：套件記錄的是整個執行所執行的內容，而非每個測試執行的內容。因此，當執行的參數略過測試時（使用 `--only`、`--exclude`、`--failed`、`--stale`、`--name-pattern`、`--max-failures`，或指定測試檔案或行），該 commit 的涵蓋率會標示為 **不完整**，除非也執行了未略過任何內容的同變體執行。兩個各自略過部分測試的執行（例如 `--exclude slow` 和 `--only slow`）仍會使 commit 不完整，即使它們合起來執行了所有測試。

某些測試是故意略過的，不會導致 commit 不完整：

- **測試輔助工具的排除項目。** `ExUnit.start(exclude: [...])` 預設略過的測試是你的專案對於套件預設執行內容的選擇，因此 Tuist 不會將其視為缺失。在另一個工作中使用 `--include` 或 `--only` 執行它們，以將其涵蓋率加入 commit。
- **在程式碼中跳過的測試**，使用 `@tag :skip`。
- **被<.localized_link href="/guides/features/test-insights/flaky-tests/elixir#quarantining">隔離</.localized_link>略過的測試。** 它們會被排除，如同已被移除，因此僅由它們涵蓋的行會計為未涵蓋。

### 完整與不完整的 commit {#commit-status}

儀表板上的每個 commit 都有狀態：

| 狀態 | 意義 |
| --- | --- |
| 進行中 | 已有執行回報涵蓋率，但尚未針對該 commit 執行 `mix tuist.coverage.complete`。 |
| 完整 | 該 commit 所有執行的測試皆已執行，或已故意略過。 |
| 不完整 | 部分涵蓋率無法判定，因此該數值為下限。 |
| 未測量 | 沒有執行回報該 commit 的涵蓋率。 |

分支趨勢僅包含完整的 commit。例如在以下情況，commit 會不完整：

- 某變體的每次執行都以其參數略過了測試。
- 某變體的每次執行都缺少部分分片。
- 某變體的涵蓋率僅來自於含有未提交變更的檢出之 CI 執行。

變體是你透過 `--scheme` 傳遞的標籤，例如資料庫版本。沒有標籤的執行屬於同一個變體。commit 的數值會合併所有執行，但 Tuist 會個別檢查每個變體的完整性，因此每個變體都需要一次未略過任何內容的執行。

## 效能影響 {#performance-impact}

收集涵蓋率會增加額外負擔，因此使用 `--cover` 的執行比未使用的執行耗時更長。首次執行會使用行計數器重新編譯你的模組；後續執行僅重新編譯變更部分，因此成本大幅降低。在大型專案中，原生計數也比 Mix 的涵蓋率工具快得多。

## 限制 {#limitations}

- **無 HTML 報告。** 原生計數不會將報告寫入 `test_coverage: [output: ...]` 目錄，且當設定該目錄時執行會發出警告。儀表板的檔案頁面會改為顯示已涵蓋的行。
- **重試不會增加涵蓋率。** 使用 <.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">測試重試</.localized_link> 時，涵蓋率以第一次嘗試為準。該次嘗試已執行失敗的測試，因此缺少的行僅限於不穩定測試在重試時觸及、但在第一次嘗試時未觸及的部分。
- **來自分支的拉取請求無涵蓋率。** 只有通過 Tuist 驗證的執行才會上傳涵蓋率，而 CI 通常會對來自分支的拉取請求保留密鑰與身分權杖，因此這些執行不會回報涵蓋率。合併後，該 commit 會在你的分支上使用憑證執行，並照常回報其涵蓋率。

## 查詢涵蓋率 {#querying}

儀表板的 **程式碼涵蓋率** 頁面顯示每個 commit 的數值、其應用程式與檔案，以及每次執行所涵蓋的行。代理程式可透過 <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol 伺服器</.localized_link> 取得相同資料。
