---
{
  "title": "Elixir 程式碼涵蓋率",
  "titleTemplate": ":title · 程式碼涵蓋率 · 功能 · 指南 · Tuist",
  "description": "使用 mix test --cover 上傳 Elixir 專案的逐行涵蓋率，並按檔案、應用程式及提交追蹤。"
}
---
# Elixir 代碼覆蓋率 {#elixir-code-coverage}

代碼覆蓋率會告訴你測試執行咗你代碼嘅邊啲行。Hex 套件會上傳每次 `mix test --cover` 運行嘅行覆蓋率，而 Tuist 會將一個 commit 嘅多次運行合併成一個數字，涵蓋整個項目、每個 OTP 應用程式同每個檔案。儀表板嘅 **代碼覆蓋率** 頁面會按 commit 顯示，並展示每個分支嘅趨勢。

> [!IMPORTANT]
> **必要條件**
>
> - 完成 <.localized_link href="/guides/get-started/elixir-project">共用 Elixir 設定</.localized_link>，此設定會將 `mix test` 透過套件進行路由

## 設定 {#setup}

### 帶覆蓋率運行測試 {#run-your-tests}

傳遞 `--cover`，就好似你喺冇 Tuist 情況下對 `mix test` 做嘅一樣：

```sh
mix test --cover
```

套件會上傳覆蓋率連同運行嘅測試結果。當測試套件完成時，它亦會執行 Mix 覆蓋率工具所做嘅事，並使用相同嘅 `test_coverage` 選項進行設定：

- **摘要。** 它會打印每個模組同總計嘅覆蓋率。`summary: false` 會關閉此功能。
- **閾值。** 當總計低於閾值時，運行會以退出狀態 3 失敗，除非你另行設定，否則閾值為 90%：

```elixir
def project do
  [
    test_coverage: [summary: [threshold: 80]]
  ]
end
```

同 Mix 一樣，閾值屬於摘要，所以 `summary: false` 會同時關閉兩者。要打印摘要但唔令運行失敗，請設定 `threshold: 0`。列於 `test_coverage: [ignore_modules: [...]]` 嘅模組會被排除喺摘要同上傳之外。

Tuist 會按 commit 追蹤覆蓋率，所以你嘅項目需要位於 Git 儲存庫中：喺儲存庫之外嘅運行會上傳測試結果，但唔會上傳覆蓋率。

覆蓋率依賴套件上傳嘅 <.localized_link href="/guides/features/test-insights/elixir#git-history">Git 歷史記錄</.localized_link>，這會將 commit 放置喺其分支上。持續集成上嘅運行總會上傳它，而 `--cover` 運行會喺任何機器上都上傳它。使用 `--cover` 時，套件亦會找出 pull request 係從邊度分支出來：它會獲取基礎分支並按需加深淺克隆。喺持續集成上，淺檢出亦會被加深（唔包含檔案內容），直到達到 Tuist 已經擁有嘅 commit，因此 commit 永遠唔會喺冇父 commit 嘅情況下上傳。設定 `TUIST_GIT_UNSHALLOW_ENABLED=false` 以防止它聯繫遠端。

### 分片運行 {#sharded-runs}

當你 <.localized_link href="/guides/features/test-sharding/elixir">分片你的測試</.localized_link> 時，用 `--cover` 運行每個分片：

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix tuist.test --cover
```

喺全新嘅 runner 上，使用分片指南中 <.localized_link href="/guides/features/test-sharding/elixir#test-phase">測試階段</.localized_link> 嘅 bootstrap 命令，這可以防止 Mix 喺分片下載其構建之前編譯每個依賴項，並向其添加 `--cover`。

分片只報告自己嘅覆蓋率且唔檢查閾值，因為它只運行套件嘅一部分。Tuist 會將一次運行嘅所有分片合併成一個數字。

每個分片會將覆蓋率計數器添加到它下載嘅構建中。要改為只做一次，請將 `--cover` 傳遞給構建階段：

```sh
MIX_ENV=test mix tuist.test.build --shard-max 5 --cover
```

當你喺流水線運行之間保留構建目錄，並喺唔收集覆蓋率嘅運行中重用時，請關閉此選項，以便該構建保持冇計數器。

### 喺 CI 上完成每個 commit {#complete-each-commit}

一個 commit 嘅覆蓋率通常來自多個作業：每個分片、每個數據庫版本或每個應用程式各一個。Tuist 無法判斷最後一個何時已報告，所以你要告訴它。當一個 commit 嘅所有測試作業完成後，喺依賴所有這些作業嘅作業中運行以下命令：

```sh
MIX_ENV=test mix tuist.coverage.complete
```

任務會從 `GIT_COMMIT` 或檢出嘅 `HEAD` 讀取 commit；傳遞 `--commit <sha>` 以指定另一個。喺 commit 完成之前，其覆蓋率會顯示為 **進行中** 且唔會計入其分支嘅趨勢。

## 運作原理 {#how-it-works}

### 原生行計數器 {#native-line-counters}

Mix 嘅覆蓋率工具會喺每次運行開始時為 Erlang 嘅 `cover` 重新編譯每個模組，這喺大型項目上會變慢。套件改為使用運行時嘅原生行計數器進行計數。它只重新編譯自上次運行以來由編譯寫入嘅模組，將運行時切換到這些計數器，並喺套件完成時讀取它們。Mix 嘅覆蓋率工具被排除，但其摘要同閾值會被保留。

套件會回退到 Mix 嘅覆蓋率工具，並使用相同嘅上傳方式，適用於：

- 傘狀項目嘅根目錄。喺每個應用程式內部運行測試以進行原生計數。
- 設定咗自己 `test_coverage: [tool: ...]` 嘅項目。
- 冇 JIT 嘅運行時，無法進行原生計數。

### Tuist 測量什麼 {#what-tuist-measures}

- **應用程式。** 每個 OTP 應用程式都係儀表板上嘅一個目標，擁有自己嘅覆蓋率。
- **僅產品代碼。** 你測試路徑下嘅檔案係測試代碼。Tuist 會儲存它們，但會將它們排除喺所有數字之外。
- **每檔案行數。** 一行喺每個檔案中只計一次，無論它屬於幾個模組。
- **函數。** 每行都屬於其上方最近開始子句嘅函數。編譯器或宏生成嘅函數，例如 `__info__/1` 或 `__schema__/1`，唔會被列出，但它們嘅行仍會計入其檔案。

因此 Tuist 嘅數字與 Mix 自己嘅覆蓋率報告有幾點不同：它們排除測試代碼，並按檔案而非按模組計數行數。原生計數亦會看到應用程式啟動時運行嘅代碼，並排除編譯器證明永遠唔會運行嘅行，而 Mix 嘅工具會將這些行報告為從未覆蓋。

### 跳過嘅測試 {#skipped-tests}

Tuist 無法延續運行所省略測試嘅覆蓋率：套件記錄係整個運行執行咗什麼，而非每個測試執行咗什麼。因此，當運行自身嘅參數省略咗測試時（使用 `--only`、`--exclude`、`--failed`、`--stale`、`--name-pattern`、`--max-failures`，或測試檔案或行），commit 嘅覆蓋率會係 **不完整**，除非亦運行咗一個冇省略任何內容嘅相同變體運行。兩個各自省略咗測試嘅運行，例如 `--exclude slow` 同 `--only slow`，仍然會使 commit 不完整，即使它們合起來運行咗每個測試。

有些測試係故意省略嘅，唔會使 commit 不完整：

- **你測試助手嘅排除項。** `ExUnit.start(exclude: [...])` 默認省略嘅測試係你項目選擇默認運行嘅套件內容，所以 Tuist 唔將它們計為缺失。喺另一個作業中用 `--include` 或 `--only` 運行它們，以將它們嘅覆蓋率添加到 commit。
- **代碼中跳過嘅測試**，使用 `@tag :skip`。
- **<.localized_link href="/guides/features/test-insights/flaky-tests/elixir#quarantining">隔離</.localized_link>跳過嘅測試。** 它們會被省略，好似被移除咗一樣，所以只有它們覆蓋嘅行會計為未覆蓋。

### 完整同不完整嘅 commit {#commit-status}

儀表板上每個 commit 都有一個狀態：

| 狀態 | 含義 |
| --- | --- |
| 進行中 | 運行已報告覆蓋率，但 `mix tuist.coverage.complete` 尚未針對該 commit 運行。 |
| 完整 | commit 運行中嘅每個測試都已運行，或係故意省略。 |
| 不完整 | 部分覆蓋率無法確定，因此該數字只係下限。 |
| 未測量 | 冇運行報告該 commit 嘅覆蓋率。 |

分支趨勢僅包含完整嘅 commit。例如，當出現以下情況時，commit 會不完整：

- 變體嘅每次運行都因其自身參數而省略咗測試。
- 變體嘅每次運行都缺少部分分片。
- 變體嘅覆蓋率僅來自於具有未提交更改嘅檢出上嘅 CI 運行。

變體係你通過 `--scheme` 傳遞嘅標籤，例如數據庫版本。冇標籤嘅運行屬於同一個變體。commit 嘅數字合併咗所有運行，但 Tuist 會單獨檢查每個變體嘅完整性，因此每個變體都需要一個冇省略任何內容嘅運行。

## 性能影響 {#performance-impact}

收集覆蓋率會增加開銷，因此帶有 `--cover` 嘅運行比唔帶它嘅運行耗時更長。第一次運行會使用行計數器重新編譯你嘅模組；後續運行僅重新編譯更改咗嘅部分，因此成本大大降低。喺大型項目中，原生計數亦比 Mix 嘅覆蓋率工具快得多。

## 限制 {#limitations}

- **冇 HTML 報告。** 原生計數唔會將報告寫入 `test_coverage: [output: ...]` 目錄，並且當設置咗該目錄時運行會發出警告。儀表板嘅檔案頁面會顯示已覆蓋嘅行。
- **重試唔會增加覆蓋率。** 使用 <.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">測試重試</.localized_link> 時，覆蓋率係第一次嘗試嘅結果。那次嘗試已經運行咗失敗嘅測試，所以唯一缺失嘅行係那些不穩定測試喺重試時達到但喺第一次嘗試時未达到嘅行。
- **來自 fork 嘅拉取請求冇覆蓋率。** 覆蓋率僅由通過 Tuist 認證嘅運行上傳，而 CI 通常會從來自 fork 嘅拉取請求中扣留密鑰同身份令牌，因此這些運行唔會報告覆蓋率。一旦合併，commit 就會憑藉憑證喺你嘅分支上運行，並照常報告其覆蓋率。

## 查詢覆蓋率 {#querying}

儀表板嘅 **代碼覆蓋率** 頁面顯示每個 commit 嘅數字、其應用程式同檔案，以及每次運行覆蓋嘅行。代理可以通過 <.localized_link href="/guides/features/agentic-coding/mcp">模型上下文協議服務器</.localized_link> 訪問相同嘅數據。
