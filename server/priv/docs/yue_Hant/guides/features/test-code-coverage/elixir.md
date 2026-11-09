---
{
  "title": "Elixir 代碼覆蓋率",
  "titleTemplate": ":title · 代碼覆蓋率 · 功能 · 指南 · Tuist",
  "description": "使用 mix test --cover 上傳 Elixir 專案的逐行覆蓋率，並按檔案、應用程式及提交記錄追蹤。"
}
---
# Elixir 程式碼覆蓋率 {#elixir-code-coverage}

程式碼覆蓋率會告訴你測試執行咗你程式碼嘅邊啲行。Hex 套件會上傳每次 `mix test --cover` 執行嘅行覆蓋率，而 Tuist 會將一個 commit 嘅多次執行合併成一個數值，涵蓋整個專案、每個 OTP 應用程式同每個檔案。儀表板嘅 **程式碼覆蓋率** 頁面會按 commit 顯示，並展示每個分支嘅趨勢。

> [!IMPORTANT]
> **必要條件**
>
> - 完成 <.localized_link href="/guides/get-started/elixir-project">共用 Elixir 設定</.localized_link>，令 `mix test` 透過套件執行

## 設定 {#setup}

### 帶覆蓋率執行測試 {#run-your-tests}

傳遞 `--cover`，就好似你喺冇 Tuist 時對 `mix test` 做嘅一樣：

```sh
mix test --cover
```

套件會上傳覆蓋率連同執行嘅測試結果。當測試套件完成時，佢亦會執行 Mix 覆蓋率工具所做嘅事，並使用相同嘅 `test_coverage` 選項進行設定：

- **摘要。** 佢會打印每個模組同總體嘅覆蓋率。`summary: false` 會關閉此功能。
- **閾值。** 當總體覆蓋率低於閾值時，執行會以退出狀態 3 失敗；除非你另行設定，否則預設為 90%：

```elixir
def project do
  [
    test_coverage: [summary: [threshold: 80]]
  ]
end
```

同 Mix 一樣，閾值屬於摘要，所以 `summary: false` 會同時關閉兩者。要打印摘要但唔令執行失敗，請設定 `threshold: 0`。列於 `test_coverage: [ignore_modules: [...]]` 嘅模組會被排除喺摘要同上傳之外。

Tuist 會按 commit 追蹤覆蓋率，所以你嘅專案需要位於 Git 儲存庫中：喺儲存庫之外執行會上傳測試結果，但唔會上傳覆蓋率。

覆蓋率依賴套件上傳嘅 <.localized_link href="/guides/features/test-insights/elixir#git-history">Git 歷史記錄</.localized_link>，從而將 commit 放置於其分支上。持續整合上嘅執行總會上傳佢，而 `--cover` 執行則會喺任何機器上都上傳佢。使用 `--cover` 時，套件亦會找出 pull request 嘅分支點：佢會抓取基礎分支並按需加深淺層克隆。設定 `TUIST_GIT_UNSHALLOW_ENABLED=false` 以防止佢聯絡遠端。

### 分片執行 {#sharded-runs}

當你 <.localized_link href="/guides/features/test-sharding/elixir">分片執行測試</.localized_link> 時，請帶 `--cover` 執行每個分片：

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix tuist.test --cover
```

喺全新嘅 runner 上，使用分片指南 <.localized_link href="/guides/features/test-sharding/elixir#test-phase">測試階段</.localized_link> 中嘅 bootstrap 指令，這可以防止 Mix 喺分片下載其構建之前編譯每個依賴項，並向其添加 `--cover`。

分片只報告其自身嘅覆蓋率且唔檢查閾值，因為佢只執行測試套件嘅一部分。Tuist 會將一次執行嘅所有分片合併成一個數值。

每個分片都會將覆蓋率計數器添加到佢下載嘅構建中。如果想只做一次，請亦向構建階段傳遞 `--cover`：

```sh
MIX_ENV=test mix tuist.test.build --shard-max 5 --cover
```

當你喺 pipeline 執行之間保留構建目錄，並喺唔收集覆蓋率嘅執行中重用佢時，請關閉此選項，令該構建保持冇計數器。

### 喺 CI 上完成每個 commit {#complete-each-commit}

一個 commit 嘅覆蓋率通常來自多個 job：每個分片、每個數據庫版本或每個應用程式各一個。Tuist 無法判斷最後一個係幾時報告嘅，所以你需要告訴佢。當一個 commit 嘅所有測試 job 都完成後，喺一個依賴於所有佢哋嘅 job 中執行以下指令：

```sh
MIX_ENV=test mix tuist.coverage.complete
```

任務會從 `GIT_COMMIT` 或 checkout 嘅 `HEAD` 讀取 commit；傳遞 `--commit <sha>` 以指定另一個。直到 commit 完成之前，其覆蓋率會顯示為 **進行中** 且唔會計入其分支嘅趨勢。

## 運作原理 {#how-it-works}

### 原生行計數器 {#native-line-counters}

Mix 嘅覆蓋率工具會喺每次執行開始時為 Erlang 嘅 `cover` 重新編譯每個模組，這喺大型專案上會變慢。套件改用運行時嘅原生行計數器進行計數。佢只重新編譯自上次執行以來由編寫產生嘅模組，將運行時切換到這些計數器，並喺測試套件完成時讀取佢哋。Mix 嘅覆蓋率工具被排除，但其摘要同閾值會被保留。

套件會回退到 Mix 嘅覆蓋率工具（使用相同嘅上傳方式），適用於：

- umbrella 專案嘅根目錄。請喺每個應用程式內部執行測試以進行原生計數。
- 自行設定 `test_coverage: [tool: ...]` 嘅專案。
- 冇 JIT 嘅運行時，無法進行原生計數。

### Tuist 測量嘅內容 {#what-tuist-measures}

- **應用程式。** 每個 OTP 應用程式都係儀表板上嘅一個目標，擁有自己嘅覆蓋率。
- **僅產品程式碼。** 位於你測試路徑下嘅檔案屬於測試程式碼。Tuist 會儲存佢哋，但會將佢哋排除喺所有數值之外。
- **每檔案行數。** 無論一行屬於幾個模組，佢喺每個檔案中只計一次。
- **函數。** 每一行都屬於其上方最近開始嘅子句所屬嘅函數。由編譯器或宏生成嘅函數（例如 `__info__/1` 或 `__schema__/1`）唔會被列出，但佢哋嘅行仍會計入其所屬檔案。

因此，Tuist 嘅數值與 Mix 自身嘅覆蓋率報告有幾處不同：佢哋排除測試程式碼，並按檔案而非按模組計算行數。原生計數亦會看到應用程式啟動時執行嘅程式碼，並排除編譯器證明永遠唔會執行嘅行，而 Mix 嘅工具會將這些行報告為從未覆蓋。

### 跳過嘅測試 {#skipped-tests}

Tuist 無法延續執行所省略測試嘅覆蓋率：套件記錄嘅係整個執行所執行嘅內容，而非每個測試執行嘅內容。因此，當執行嘅參數省略測試時（使用 `--only`、`--exclude`、`--failed`、`--stale`、`--name-pattern`、`--max-failures`，或測試檔案或行），該 commit 嘅覆蓋率會顯示為 **不完整**，除非亦運行咗一個冇省略任何內容嘅相同變體執行。兩個各自省略測試嘅執行（例如 `--exclude slow` 同 `--only slow`）仍然會令 commit 不完整，即使佢哋合起來執行咗所有測試。

有些測試係故意省略嘅，唔會令 commit 變得 incomplete：

- **你測試助手嘅排除項。** `ExUnit.start(exclude: [...])` 預設省略嘅測試係你專案對其套件預設運行內容嘅選擇，所以 Tuist 唔會將佢哋計為缺失。喺另一個 job 中使用 `--include` 或 `--only` 運行佢哋，以將其覆蓋率添加到 commit。
- **程式碼中跳過嘅測試**，使用 `@tag :skip`。
- **<.localized_link href="/guides/features/test-insights/flaky-tests/elixir#quarantining">隔離</.localized_link>跳過嘅測試。** 佢哋會被省略，就好似被移除咗一樣，所以只有佢哋覆蓋嘅行會計作未覆蓋。

### 完整同不完整嘅 commit {#commit-status}

儀表板上每個 commit 都有一個狀態：

| 狀態 | 含義 |
| --- | --- |
| 進行中 | 已有執行報告覆蓋率，但 `mix tuist.coverage.complete` 尚未針對該 commit 運行。 |
| 完整 | 該 commit 所有執行中嘅每個測試都已運行，或係故意省略。 |
| 不完整 | 部分覆蓋率無法確定，因此該數值為下限。 |
| 未測量 | 冇執行報告該 commit 嘅覆蓋率。 |

分支嘅趨勢僅包含完整嘅 commit。當出現以下情況時，commit 會不完整：

- 某個變體嘅每次執行都因其自身參數而省略咗測試。
- 某個變體嘅每次執行都缺少部分分片。
- 某個變體嘅覆蓋率僅來自於含有未提交更改嘅 checkout 上嘅 CI 執行。

變體係你透過 `--scheme` 傳遞嘅標籤，例如數據庫版本。冇標籤嘅執行屬於同一個變體。Commit 嘅數值會合併所有執行，但 Tuist 會單獨檢查每個變體嘅完整性，因此每個變體都需要一個冇省略任何內容嘅執行。

## 性能影響 {#performance-impact}

收集覆蓋率會增加開銷，所以帶有 `--cover` 嘅執行比冇帶佢嘅執行耗時更長。第一次執行會使用行計數器重新編譯你嘅模組；後續執行只重新編譯發生變化嘅部分，因此開銷小得多。喺大型專案中，原生計數亦比 Mix 嘅覆蓋率工具快得多。

## 限制 {#limitations}

- **冇 HTML 報告。** 原生計數唔會向 `test_coverage: [output: ...]` 目錄寫入報告，並且當設置咗該目錄時執行會發出警告。儀表板嘅檔案頁面會顯示已覆蓋嘅行作為替代。
- **重試唔會增加覆蓋率。** 使用 <.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">測試重試</.localized_link> 時，覆蓋率係第一次嘗試嘅結果。該次嘗試已經運行咗失敗嘅測試，所以唯一缺失嘅行係那些不穩定測試喺重試時達到但喺第一次嘗試時未達到嘅行。
- **冇來自 fork 嘅 pull request 嘅覆蓋率。** 覆蓋率僅由通過 Tuist 認證嘅執行上傳，而 CI 通常會扣留來自 fork 開啟嘅 pull request 嘅密鑰同身份令牌，因此這些執行唔會報告覆蓋率。一旦合併，該 commit 會憑藉憑證喺你嘅分支上運行，並照常報告其覆蓋率。

## 查詢覆蓋率 {#querying}

儀表板嘅 **程式碼覆蓋率** 頁面顯示每個 commit 嘅數值、其應用程式同檔案，以及每次執行覆蓋嘅行。代理可以透過 <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol 伺服器</.localized_link> 獲取相同嘅數據。
