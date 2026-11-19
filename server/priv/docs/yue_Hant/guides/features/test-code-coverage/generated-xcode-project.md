---
{
  "title": "生成的 Xcode 專案",
  "titleTemplate": ":title · 程式碼涵蓋率 · 功能 · 指南 · Tuist",
  "description": "按檔案及提交記錄，測量由 Tuist 生成的 Xcode 專案的程式碼涵蓋率，包括被二進制快取和選擇性測試跳過的程式碼。"
}
---
# 已產生嘅 Xcode 專案 {#generated-xcode-project-code-coverage}

代碼覆蓋率會話你知邊啲代碼行被測試執行過。Tuist 會上傳每次 `tuist test` 執行嘅行覆蓋率，並將同一個 commit 嘅多次執行合併成一個數字，涵蓋整個專案、每個 target 同每個檔案。Dashboard 嘅 **代碼覆蓋率** 頁面會按 commit 顯示，並呈現每個 branch 嘅趨勢。

<!-- @snippet: ./_xcode-requirements -->

當 Tuist 跳過部分工作時，數字仍然準確。你從 <.localized_link href="/guides/features/cache/module-cache">binary cache</.localized_link> 取得嘅 target 係連同覆蓋率計數器一齊編譯嘅，所以佢哋嘅代碼會好似從原始碼編譯咁被測量。而當 <.localized_link href="/guides/features/selective-testing/generated-xcode-project">選擇性測試</.localized_link> 跳過某個測試 target 時，該 target 會保留之前執行中獲得嘅覆蓋率，因為 Tuist 會在每次執行時記錄 [target 層級覆蓋率](#target-level-coverage)。

## 設定 {#setup}

### 開啟覆蓋率 {#turn-coverage-on}

喺你嘅 `Tuist.swift` 產生選項中開啟覆蓋率，並啟用預設關閉嘅覆蓋率上傳功能：

```swift
import ProjectDescription

let tuist = Tuist(
    testInsights: .testInsights(coverage: .coverage(upload: true)),
    project: .tuist(
        generationOptions: .options(
            coverage: .coverage(enabled: true)
        )
    )
)
```

開啟產生選項後：

- Tuist 產生嘅每個 scheme 嘅測試動作都會收集覆蓋率；你定義嘅 scheme 如果無設定 `coverage`，其測試動作亦會收集覆蓋率。設有 `.options(coverage: false)` 或 `.options(coverage: true)` 嘅 scheme 會保留其設定值。Test plan 會自行決定覆蓋率：對於 Tuist 產生嘅 test plan，請將 `coverage: true` 傳遞畀 `.testPlans(_:coverage:)`。
- 你專案自身嘅 target 會以 Debug 設定下帶覆蓋率計數器嘅形式，從 binary cache 讀取同預熱。參閱 [運作原理](#instrumented-binaries)。

環境變數 `TUIST_COVERAGE_ENABLED` 同 `TUIST_COVERAGE_UPLOAD`（`1` 或 `0`）嘅優先級高於 `enabled` 同 `upload`。請為整個環境（例如 CI workflow）設定，而唔係為單一指令設定，確保預熱 cache 同讀取 cache 嘅指令保持一致。

> [!IMPORTANT] KEEP THE VALUE THE SAME EVERYWHERE
> 產生選項會改變你專案 target 嘅 cache key 同測試 target 嘅選擇性測試 hash。喺所有共用 cache 嘅機器上使用相同嘅值，唔好從環境衍生（例如從 `Environment.isCI`）。關閉覆蓋率嘅執行無法重用開啟覆蓋率執行所產生嘅 binary 或選擇性測試結果。

### 排除 scheme {#leave-schemes-out}

有啲測試套件唔應該納入你嘅覆蓋率範圍。例如，從另一個程序驅動你嘅 app 或 CLI 嘅驗收測試或端到端測試，會執行覆蓋率工具睇唔到嘅代碼，收集覆蓋率只會令佢哋變慢。請喺佢哋 scheme 嘅測試動作中關閉覆蓋率：

```swift
.scheme(
    name: "AcceptanceTests",
    testAction: .targets(
        ["AcceptanceTests"],
        options: .options(coverage: false)
    )
)
```

無論 `Tuist.swift` 選項或 `TUIST_COVERAGE_ENABLED` 點設定，該 scheme 都會保持覆蓋率關閉，其執行亦不會計入 commit 嘅覆蓋率。覆蓋率係按 scheme 收集嘅，所以要排除某個測試 target，請將佢移到自己專屬嘅 scheme。

### 執行測試 {#run-your-tests}

照常使用 `tuist test` 執行測試：

```sh
tuist test
```

Tuist 會上傳執行期間收集嘅覆蓋率連同測試結果。這包括 <.localized_link href="/guides/features/test-sharding/generated-xcode-project">分片執行</.localized_link> 同使用 `--without-building` 喺另一個 job 中構建產品嘅測試執行。如果想讓某次執行嘅覆蓋率唔上傳至 Tuist（例如處理來自 fork 嘅 pull request 嘅 job），請設定 `TUIST_COVERAGE_UPLOAD=0`。

### 喺 CI 上完成每個 commit {#complete-each-commit}

一個 commit 嘅覆蓋率通常來自多個 job：每個 scheme、每個分片或每個平台各一個。Tuist 無法判斷最後一個 job 何時匯報，所以需要你自己通知。當一個 commit 嘅所有測試 job 完成後，喺依賴晒佢哋嘅 job 中執行以下指令：

```sh
tuist coverage complete
```

該指令會從 checkout 嘅 `HEAD` 讀取 commit，即係你測試運行所在嘅 commit；傳遞 `--commit <sha>` 可以指定另一個 commit。喺 commit 完成之前，其覆蓋率會顯示為 **進行中**，且不會納入其 branch 嘅趨勢。

### 喺預設 branch 上執行完整套件 {#full-runs}

> [!IMPORTANT] SET UP A FULL RUN
> 只有當有先前嘅執行來承接被跳過嘅 target 時，選擇性測試才能保持 commit 覆蓋率完整。請喺你嘅預設 branch 上安排一次唔使用選擇性測試嘅完整測試執行：
>
> ```sh
> tuist test --no-selective-testing
> ```
>
> 理想情況係每次 merge 都執行一次。對於變更較少嘅倉庫，每日或每週執行可能已足夠。記錄嘅覆蓋率會喺 31 日後過期，所以執行頻率應高於此。

承接嘅覆蓋率依賴完整執行。佢哋會喺過期前刷新每個 target 嘅記錄覆蓋率，並為 Tuist 提供選擇性執行未構建檔案嘅最新狀態。倉庫喺兩次完整執行之間變更越多，選擇性執行就越常發現自上次以來已變更嘅檔案，導致其 commit 覆蓋率顯示為 **不完整**。

## Target 層級覆蓋率 {#target-level-coverage}

一次執行嘅覆蓋率反映成個執行過程執行咗乜，而唔係每個測試 target 分別執行咗乜。當選擇性測試跳過某個 target 時，Tuist 需要知道該 target 喺先前執行中執行咗乜，以便承接其覆蓋率。

因此，Tuist 會喺每次執行時記錄每個測試 target 執行咗邊啲檔案同行。數據來自 Xcode 為每個測試進程寫入嘅覆蓋率，無需額外連結或設定。這僅喺 macOS 同 iOS 模擬器上記錄，設備上則否。UI 測試不會記錄佢所驅動 app 嘅任何信息，因為 app 代碼喺自己嘅進程中運行。

## 運作原理 {#how-it-works}

### 插樁 Binary {#instrumented-binaries}

來自 binary cache 嘅 target 係預先構建嘅 binary，測試執行只有喺 binary 連同覆蓋率計數器構建時才能測量其代碼。開啟覆蓋率後，binary cache 會保存你專案自身 target 嘅插樁版本，每個指令都會讀取同預熱該版本：

- **Debug 設定** 使用插樁版本：`tuist cache` 負責預熱，而 `tuist generate` 同 `tuist test` 負責讀取。
- **Release 設定** 始終使用普通版本，所以你發佈嘅產品永遠唔會帶有覆蓋率計數器。
- **外部套件** 始終使用普通版本。Tuist 只測量你倉庫嘅代碼。

請喺與測試 job 相同嘅環境中開啟覆蓋率來預熱 cache，確保 `tuist test` 能找到插樁 binary。如果一次執行收集覆蓋率但從 cache 取得嘅係普通 binary，Tuist 會發出警告，且該代碼不會被測量。<.localized_link href="/guides/features/cache/module-cache#code-coverage">module cache</.localized_link> 詳細記錄咗呢啲版本。

### 跨機器路徑 {#paths-across-machines}

插樁 binary 會記錄相對於構建時 checkout 嘅原始碼路徑，因此喺 CI 上預熱嘅 binary 能喺任何開發者嘅機器上正確測量檔案。

<.localized_link href="/guides/features/cache/xcode-cache">Xcode cache</.localized_link> 透過路徑前綴映射以相同方式運作。Tuist 預設會喺收集覆蓋率嘅構建中關閉此功能，因為 Xcode 自身嘅覆蓋率報告無法解析映射後嘅路徑。喺 Xcode 27 及更高版本中，開啟 `enableCaching` 後，`prefixMapping: true` 會保持其啟用狀態，令覆蓋率構建亦能喺唔同 checkout 之間共享編譯結果：

```swift
.options(coverage: .coverage(enabled: true, prefixMapping: true))
```

Tuist 嘅上傳會解析映射後嘅路徑，但 Xcode 嘅覆蓋率報告同 `xccov` 可能會遺漏呢啲檔案。請參閱 <.localized_link href="/guides/features/cache/xcode-cache#coverage-with-prefix-mapping">帶路徑前綴映射嘅覆蓋率</.localized_link>。

### 跳過嘅測試 {#skipped-tests}

當先前通過嘅執行已使用相同雜湊值測試咗某個測試 target 時，選擇性測試會跳過該 target。雜湊值涵蓋 target 嘅原始碼、其測試及所有依賴項，因此相同雜湊值意味著對相同代碼進行相同測試。Tuist 會重用先前執行為該 target 記錄嘅 [target 層級覆蓋率](#target-level-coverage)。如果當時無記錄（例如因為當時覆蓋率已關閉，或執行超過 31 日），則無數據可承接，該 commit 會被標記為 **不完整**。

選擇性執行亦不會構建每個檔案。對於佢未編譯嘅檔案，只要檔案自上次完整執行以來未發生變化，Tuist 就會採用最近一次完整執行中嘅行數據。這就係點解你預設分支上嘅 [完整執行](#full-runs) 如此重要。

你自行使用 `--skip-test-targets` 或 `-skip-testing` 跳過嘅測試不會被承接：如果某次執行跳過咗佢哋，且該 commit 下無其他執行運行過佢哋，則該 commit 會被標記為 **不完整**。被隔離機制跳過嘅測試完全不屬於覆蓋率範圍：Tuist 既不會承接佢哋，亦不會因此將 commit 標記為 **不完整**。

### 完整與不完整嘅 Commit {#commit-status}

儀表板上每個 commit 都有一個狀態：

| 狀態 | 含義 |
| --- | --- |
| 進行中 | 已有執行報告覆蓋率，但尚未為該 commit 運行 `tuist coverage complete`。 |
| 完整 | 該 commit 相關 scheme 嘅所有測試均已運行或被承接。 |
| 不完整 | 部分覆蓋率無法確定，因此數值僅為下限。 |
| 未測量 | 無執行為該 commit 報告覆蓋率。 |

分支趨勢僅包含完整嘅 commit。例如，以下情況會導致 commit 不完整：

- 選擇性測試跳過咗一個無法承接嘅 target：先前執行未記錄其覆蓋率、選擇性執行未構建嘅檔案自上次完整執行以來發生咗變化，或者 commit 更改咗影響所有 target 嘅檔案，例如 `Package.resolved`、`Project.swift` 或 `.xcconfig`。
- 某次執行使用 `--skip-test-targets` 或 `-skip-testing` 跳過咗測試，且該 commit 下無其他執行運行過佢哋。
- 某次執行從 binary cache 取得嘅係普通 binary 而非插樁版本。
- 某個 scheme 嘅每次執行都使用 `-only-testing` 進行咗縮減。
- 某個 scheme 嘅覆蓋率僅來自含有未提交更改嘅 checkout 上嘅 CI 執行。

## 性能影響 {#performance-impact}

收集覆蓋率會增加額外開銷，主要發生喺測試完成後，Xcode 寫入覆蓋率報告同 Tuist 導出覆蓋率數據嘅期間。構建和運行測試嘅時間與未開啟覆蓋率時大致相同。插樁構建亦會佔用更多磁盤空間，包括 DerivedData 同 Debug binary cache。Release 構建同歸檔不受影響。

## 限制 {#limitations}

### 收集覆蓋率 Scheme 嘅 Release 構建 {#release-builds}

當 scheme 嘅測試動作收集覆蓋率時，Xcode 亦會對 `xcodebuild build` 為該 scheme 從原始碼編譯嘅 target 進行插樁，適用於任何設定，包括 Release。`xcodebuild archive` 會忽略此設定，因此歸檔永遠不會被插樁。請分發歸檔文件，或使用帶有 `.options(coverage: false)` 嘅 scheme 來構建 Release 產品。

### 其他覆蓋率工具 {#other-coverage-tools}

`-enableCodeCoverage YES` 僅決定執行是否收集覆蓋率，如同喺 Xcode 中一樣。它不會令 Tuist 從 cache 讀取插樁 binary，因此請改用 `Tuist.swift` 選項或 `TUIST_COVERAGE_ENABLED`。

若要為其他覆蓋率工具提供數據，請讓 `tuist test` 將每次執行嘅覆蓋率寫入為 LCOV 格式。這與 Tuist 上傳嘅覆蓋率相同，包含相對於倉庫嘅路徑以及來自 binary cache 嘅代碼：

```sh
tuist test --coverage-output-path coverage
```

每次執行會寫入 `coverage/<result bundle name>.lcov`。請使用 `lcov -a` 合併分片執行嘅文件。此選項需要開啟覆蓋率上傳。

Xcode 自身嘅覆蓋率報告及讀取該報告嘅工具，僅包含 Xcode 喺該次執行中構建嘅 target，絕不包含來自 binary cache 嘅代碼。Tuist 嘅上傳則會測量兩者。如果你希望喺 Xcode 報告中看到某個 target 嘅覆蓋率，請生成專案時讓該 target 從原始碼構建：`tuist generate MyTarget` 會保持 `MyTarget` 為原始碼構建，並從 cache 獲取其餘部分。

## 查詢覆蓋率 {#querying}

`tuist coverage` 指令會讀取儀表板顯示嘅內容。若無指定 `--commit`，佢哋會讀取 `--branch` 或你預設分支上最新嘅完整 commit：

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
tuist coverage targets                       # targets, least covered first, then those taken from the binary cache without coverage
tuist coverage commits --branch main         # a branch's commits with their status and change, newest first
tuist coverage runs --commit <sha>           # the test runs behind a commit, marked full, partial or discarded
tuist coverage branches                      # the branches with coverage
```

測試執行自身嘅覆蓋率顯示喺 `tuist test show <test-run-id>` 中。

所有指令均接受 `--json` 以便腳本化處理。代理亦可透過 <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol server</.localized_link> 訪問相同數據。
