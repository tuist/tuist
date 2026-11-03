---
{
  "title": "Elixir 代碼覆蓋率",
  "titleTemplate": ":title · 代碼覆蓋率 · 功能 · 指南 · Tuist",
  "description": "使用 mix test --cover 上傳 Elixir 專案的行覆蓋率，並按檔案、應用程式及提交追蹤。"
}
---
# Elixir 程式碼覆蓋率 {#elixir-code-coverage}

程式碼覆蓋率會告訴你測試執行咗邊啲行。Hex package 會上傳每次 `mix test --cover` 執行嘅行覆蓋率，而 Tuist 會將一個 commit 嘅多次執行合併成一個數值，分別針對整個專案、每個 OTP application 同每個檔案。Dashboard 嘅 **Code Coverage** 頁面會按 commit 顯示，並展示每個 branch 嘅趨勢。

> [!IMPORTANT] REQUIREMENTS
> - 完成 <.localized_link href="/guides/get-started/elixir-project">shared Elixir setup</.localized_link>，佢會將 `mix test` 透過 package 路由

## 設定 {#setup}

### 帶覆蓋率執行測試 {#run-your-tests}

傳遞 `--cover`，就好似你喺冇 Tuist 嘅情況下對 `mix test` 做嘅咁：

```sh
mix test --cover
```

Package 會連同執行嘅測試結果一齊上傳覆蓋率。當測試套件完成時，佢亦會執行 Mix 覆蓋率工具嘅功能，並使用相同嘅 `test_coverage` 選項進行設定：

- **摘要。** 佢會列印每個 module 嘅覆蓋率同總計。`summary: false` 會關閉此功能。
- **閾值。** 當總計低於閾值時，執行會以退出狀態 3 失敗；除非你另行設定，否則閾值為 90%：

```elixir
def project do
  [
    test_coverage: [summary: [threshold: 80]]
  ]
end
```

同 Mix 一樣，閾值屬於摘要部分，所以 `summary: false` 會同時關閉兩者。要列印摘要但唔令執行失敗，請設定 `threshold: 0`。列於 `test_coverage: [ignore_modules: [...]]` 嘅 modules 會被排除於摘要同上傳之外。

Tuist 會按 commit 追蹤覆蓋率，所以你嘅專案需要位於 Git repository 入面：喺外面執行會上傳測試結果，但唔會上傳覆蓋率。

覆蓋率依賴 package 上傳嘅 <.localized_link href="/guides/features/test-insights/elixir#git-history">Git history</.localized_link>，從而將 commit 放置於其 branch 上。Continuous integration 上嘅執行總會上傳，而 `--cover` 執行則會喺任何機器上都上傳。使用 `--cover` 時，package 亦會搵到 pull request 係從邊度分支出來：佢會抓取 base branch 並按需加深 shallow clone。設定 `TUIST_GIT_UNSHALLOW_ENABLED=false` 以防止佢聯絡 remote。

### 分片執行 {#sharded-runs}

當你 <.localized_link href="/guides/features/test-sharding/elixir">shard your tests</.localized_link> 時，請帶 `--cover` 執行每個 shard：

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix tuist.test --cover
```

喺全新 runner 上，使用 sharding guide 中 <.localized_link href="/guides/features/test-sharding/elixir#test-phase">test phase</.localized_link> 嘅 bootstrap 指令，佢可以防止 Mix 喺 shard 下載其 build 之前編譯每個 dependency，並向其加入 `--cover`。

Shard 只會報告自己嘅覆蓋率，亦唔會檢查閾值，因為佢只執行套件嘅一部分。Tuist 會將一次執行嘅多個 shard 合併成一個數值。

每個 shard 會將覆蓋率計數器加到佢下載嘅 build 中。如果想只做一次，請亦向 build phase 傳遞 `--cover`：

```sh
MIX_ENV=test mix tuist.test.build --shard-max 5 --cover
```

當你喺 pipeline 執行之間保留 build directory，並喺唔收集覆蓋率嘅執行中重用佢時，請關閉此選項，令該 build 保持冇計數器。

### 喺 CI 上完成每個 commit {#complete-each-commit}

一個 commit 嘅覆蓋率通常來自多個 job：每個 shard、每個數據庫版本或每個 application 各一個。Tuist 無法判斷最後一個何時已報告，所以你要告訴佢。當一個 commit 嘅所有測試 job 都完成後，喺一個依賴晒佢哋嘅 job 中執行以下指令：

```sh
MIX_ENV=test mix tuist.coverage.complete
```

任務會從 `GIT_COMMIT` 或 checkout 嘅 `HEAD` 讀取 commit；傳遞 `--commit <sha>` 以指定另一個。喺 commit 完成之前，其覆蓋率會顯示為 **In progress**，並且唔會計入其 branch 嘅趨勢。

## 運作原理 {#how-it-works}

### 原生行計數器 {#native-line-counters}

Mix 嘅覆蓋率工具會喺每次執行開始時，為 Erlang 嘅 `cover` 重新編譯每個 module，這喺大型專案上會變慢。Package 改為使用 runtime 嘅原生行計數器進行計數。佢只會重新編譯自上次執行以來由編譯寫入嘅 modules，將 runtime 切換到呢啲計數器，並喺套件完成時讀取佢哋。Mix 嘅覆蓋率工具會被略過，但其摘要同閾值會保留。

對於以下情況，Package 會回退到 Mix 嘅覆蓋率工具，並以上傳相同數據：

- Umbrella project 嘅根目錄。請喺每個 application 內部執行測試以進行原生計數。
- 自行設定 `test_coverage: [tool: ...]` 嘅專案。
- 冇 JIT 嘅 runtime，無法進行原生計數。

### Tuist 測量乜嘢 {#what-tuist-measures}

- **Applications。** 每個 OTP application 係 dashboard 上嘅一個 target，擁有自己嘅覆蓋率。
- **僅產品程式碼。** 位於你測試路徑下嘅檔案屬於測試程式碼。Tuist 會儲存佢哋，但會將佢哋排除於所有數值之外。
- **每檔案行數。** 一行喺每個檔案中只計一次，無論佢屬於幾多個 modules。
- **Functions。** 每一行都屬於其上最近開始嘅 clause 所屬嘅 function。編譯器或 macro 生成嘅 functions（例如 `__info__/1` 或 `__schema__/1`）唔會列出，但佢哋嘅行仍會計入其檔案。

因此，Tuist 嘅數值同 Mix 自己嘅覆蓋率報告有幾處唔同：佢哋排除測試程式碼，並按檔案而非按 module 計行。原生計數亦會看到應用程式啟動時運行嘅程式碼，並排除編譯器證明永遠唔會運行嘅行，而 Mix 嘅工具會將呢啲行報告為從未覆蓋。

### 跳過嘅測試 {#skipped-tests}

Tuist 無法延續被執行略過嘅測試嘅覆蓋率：package 記錄嘅係整個執行所執行嘅內容，而非每個測試執行嘅內容。因此，當執行自身嘅參數略過測試時（使用 `--only`、`--exclude`、`--failed`、`--stale`、`--name-pattern`、`--max-failures`，或測試檔案或行），該 commit 嘅覆蓋率會顯示為 **Incomplete**，除非亦運行咗一個冇略過任何內容嘅相同 variant 執行。兩個各自略過測試嘅執行（例如 `--exclude slow` 同 `--only slow`）仍然會令 commit 不完整，即使佢哋合埋運行咗所有測試。

有些測試係故意略過，並唔會令 commit 不完整：

- **你測試 helper 嘅排除項。**`ExUnit.start(exclude: [...])` 預設略過嘅測試係你專案選擇預設運行嘅套件內容，所以 Tuist 唔會將佢哋計為缺失。喺另一個 job 中使用 `--include` 或 `--only` 運行佢哋，以將其覆蓋率加入 commit。
- **程式碼中跳過嘅測試**，使用 `@tag :skip`。
- **被 <.localized_link href="/guides/features/test-insights/flaky-tests/elixir#quarantining">quarantine</.localized_link> 跳過嘅測試。** 佢哋被略過，就好似被刪除咗一樣，所以只有佢哋覆蓋嘅行會被計為未覆蓋。

### 完整同不完整嘅 commits {#commit-status}

Dashboard 上每個 commit 都有一個狀態：

| 狀態 | 意思 |
| --- | --- |
| 進行中 | 已有執行回報覆蓋率，但 `mix tuist.coverage.complete` 尚未為該 commit 運行。 |
| 完整 | 該 commit 所有執行嘅測試均已運行，或係故意略過。 |
| 不完整 | 部分覆蓋率無法確定，因此數值只係下限。 |
| 未測量 | 冇任何執行為該 commit 回報覆蓋率。 |

分支嘅趨勢只包含完整嘅 commits。例如，當出現以下情況時，commit 會被視為不完整：

- 某個 variant 嘅每次執行都因其自身參數而略過咗測試。
- 某個 variant 嘅每次執行都缺少部分 shards。
- 某個 variant 嘅覆蓋率僅來自於含有未提交更改嘅 checkout 上嘅 CI 執行。

Variant 係你透過 `--scheme` 傳遞嘅標籤，例如數據庫版本。冇標籤嘅執行屬於同一個 variant。Commit 嘅數值會合併所有執行，但 Tuist 會單獨檢查每個 variant 嘅完整性，所以每個 variant 都需要一次冇略過任何內容嘅執行。

## 性能影響 {#performance-impact}

收集覆蓋率會增加開銷，所以帶有 `--cover` 嘅執行比唔帶佢嘅執行耗時更長。第一次執行會使用行計數器重新編譯你嘅 modules；後續執行只重新編譯更改過嘅部分，所以開銷小得多。喺大型專案中，原生計數亦比 Mix 嘅覆蓋率工具快得多。

## 限制 {#limitations}

- **冇 HTML 報告。** 原生計數唔會將報告寫入 `test_coverage: [output: ...]` 目錄，並且當設置咗該目錄時，執行會發出警告。Dashboard 嘅檔案頁面會改為顯示已覆蓋嘅行。
- **重試唔會增加覆蓋率。** 使用 <.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">test retries</.localized_link> 時，覆蓋率係第一次嘗試嘅結果。該次嘗試已經運行咗失敗嘅測試，所以唯一缺失嘅行係那些 flaky test 喺重試時達到但喺第一次嘗試時未達到嘅行。
- **來自 fork 嘅 pull requests 冇覆蓋率。** 覆蓋率僅由通過 Tuist 認證嘅執行上傳，而 CI 通常會從來自 fork 嘅 pull requests 中扣留 secrets 同 identity tokens，所以呢啲執行唔會回報覆蓋率。一旦合併，該 commit 會憑藉憑證喺你嘅分支上運行，並照常回報其覆蓋率。

## 查詢覆蓋率 {#querying}

Dashboard 嘅 **Code Coverage** 頁面顯示每個 commit 嘅數值、其 applications 同 files，以及每次執行覆蓋嘅行。Agents 可以透過 <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol server</.localized_link> 訪問相同嘅數據。
