---
{
  "title": "生成嘅 Xcode 專案",
  "titleTemplate": ":title · 代碼覆蓋率 · 功能 · 指南 · Tuist",
  "description": "按檔案同提交記錄，量度由 Tuist 生成嘅 Xcode 專案嘅代碼覆蓋率，包括被二進制快取同選擇性測試跳過嘅代碼。"
}
---
# 已產生嘅 Xcode 專案 {#generated-xcode-project-code-coverage}

代碼覆蓋率會顯示你嘅測試執行咗邊啲代碼行。Tuist 會上傳每次 `tuist test` 執行嘅行覆蓋率，並將同一個 commit 嘅多次執行合併成一個數字，適用於整個專案、每個 target 同每個檔案。儀表板嘅 **代碼覆蓋率** 頁面會按 commit 顯示，並呈現每個分支嘅趨勢。

<!-- @snippet: ./_xcode-requirements -->

當 Tuist 跳過部分工作時，數字仍然準確。你從 <.localized_link href="/guides/features/cache/module-cache">二進制快取</.localized_link> 取得嘅 target 會連同覆蓋率計數器一齊編譯，所以佢哋嘅代碼會好似從原始碼編譯嘅代碼一樣被測量。而當 <.localized_link href="/guides/features/selective-testing/generated-xcode-project">選擇性測試</.localized_link> 跳過某個測試 target 時，該 target 會保留之前執行中嘅覆蓋率數據，透過 Tuist 在每次執行時記錄嘅 [target 層級覆蓋率](#target-level-coverage) 來實現。

## 設定 {#setup}

### 開啟覆蓋率 {#turn-coverage-on}

喺你 `Tuist.swift` 嘅產生選項中開啟覆蓋率，並啟用預設關閉嘅覆蓋率上傳功能：

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

- Tuist 產生嘅每個 scheme 嘅測試動作都會收集覆蓋率，你自己定義但將 `coverage` 留空嘅 scheme 嘅測試動作亦然。設有 `.options(coverage: false)` 或 `.options(coverage: true)` 嘅 scheme 會保留其設定值。測試計劃自行決定覆蓋率：對於 Tuist 產生嘅測試計劃，請向 `.testPlans(_:coverage:)` 傳遞 `coverage: true`。
- 你專案自身嘅 target 會在 Debug 組態下，連同覆蓋率計數器一齊從二進制快取讀取及預熱。參閱 [運作原理](#instrumented-binaries)。

`TUIST_COVERAGE_ENABLED` 同 `TUIST_COVERAGE_UPLOAD` 環境變數（`1` 或 `0`）優先於 `enabled` 同 `upload`。請為整個環境（例如 CI 工作流程）設定，而唔係為單一指令設定，以便預熱快取同讀取快取嘅指令保持一致。

> [!IMPORTANT] KEEP THE VALUE THE SAME EVERYWHERE
> 產生選項會改變你專案 target 嘅快取鍵值同測試 target 嘅選擇性測試哈希值。喺所有共用快取嘅機器上使用相同嘅值，唔好從環境衍生（例如從 `Environment.isCI`）。關閉覆蓋率嘅執行不會重用開啟覆蓋率執行所產生嘅二進制文件或選擇性測試結果。

### 排除 Scheme {#leave-schemes-out}

有些測試套件唔應該納入你嘅覆蓋率計算。例如，從另一個程序驅動你嘅 App 或 CLI 嘅驗收測試或端到端測試，會執行覆蓋率工具無法偵測嘅代碼，收集这些数据只會令佢哋變慢。請喺佢哋 scheme 嘅測試動作中關閉覆蓋率：

```swift
.scheme(
    name: "AcceptanceTests",
    testAction: .targets(
        ["AcceptanceTests"],
        options: .options(coverage: false)
    )
)
```

無論 `Tuist.swift` 選項或 `TUIST_COVERAGE_ENABLED` 點設定，該 scheme 都會保持關閉覆蓋率，且其執行不會計入 commit 嘅覆蓋率。覆蓋率係按 scheme 收集嘅，所以如果要排除某個測試 target，請將佢移至獨立嘅 scheme。

### 執行你嘅測試 {#run-your-tests}

照常使用 `tuist test` 執行你嘅測試：

```sh
tuist test
```

Tuist 會上傳執行期間收集嘅覆蓋率連同測試結果。這包括 <.localized_link href="/guides/features/test-sharding/generated-xcode-project">分片執行</.localized_link> 同使用 `--without-building` 喺另一個 job 中構建產品並進行測試嘅執行。如果要防止某次執行嘅覆蓋率上傳至 Tuist（例如喺運行來自 fork 嘅 pull request 嘅 job 中），請設定 `TUIST_COVERAGE_UPLOAD=0`。

### 喺 CI 上完成每個 Commit {#complete-each-commit}

一個 commit 嘅覆蓋率通常來自多個 job：每個 scheme、每個分片或每個平台各一個。Tuist 無法判斷最後一個 job 何時匯報完畢，所以需要你去通知。當某個 commit 嘅所有測試 job 都完成後，請喺依賴晒佢哋嘅 job 中運行以下指令：

```sh
tuist coverage complete
```

該指令會從 checkout 嘅 `HEAD`（即你測試運行所在嘅 commit）讀取 commit；傳遞 `--commit <sha>` 以指定另一個 commit。喺 commit 完成之前，其覆蓋率會顯示為 **進行中**，並且不會納入其分支嘅趨勢。

### 喺你嘅預設分支上運行完整套件 {#full-runs}

> [!IMPORTANT] SET UP A FULL RUN
> 只有當有早期執行可以攜帶被跳過嘅 target 時，選擇性測試才能保持 commit 嘅覆蓋率完整。請喺你嘅預設分支上安排一次不進行選擇性測試嘅完整測試執行：
>
> ```sh
> tuist test --no-selective-testing
> ```
>
> 理想情況下，每次合併都運行一次。對於變更較少嘅儲存庫，每日或每週運行一次可能已經足夠。記錄嘅覆蓋率會喺 31 天後過期，所以請比這個頻率更頻繁地運行。

攜帶嘅覆蓋率依賴於完整執行。佢哋會喺過期前刷新每個 target 嘅記錄覆蓋率，並為 Tuist 提供選擇性執行未構建文件嘅最新狀態。儲存庫喺兩次完整執行之間嘅變更越多，選擇性執行就越經常發現自上次以來已變更嘅文件，導致其 commit 嘅覆蓋率顯示為 **不完整**。

## Target 層級覆蓋率 {#target-level-coverage}

一次執行嘅覆蓋率顯示的是整個執行所運行嘅內容，而非每個測試 target 各自運行嘅內容。當選擇性測試跳過某個 target 時，Tuist 需要知道該 target 喺早期執行中運行咗乜嘢，以便攜帶其覆蓋率數據。

因此，喺每次執行中，Tuist 亦會記錄每個測試 target 執行咗邊啲文件同行。它從 Xcode 為每個測試進程寫入嘅覆蓋率數據中讀取呢啲資訊，所以無需額外連結或設定。這僅喺 macOS 同 iOS 模擬器上記錄，設備上則不會。UI 測試不會記錄佢所驅動 App 嘅任何資訊，因為 App 嘅代碼喺獨立進程中運行。

## 運作原理 {#how-it-works}

### 插樁二進制文件 {#instrumented-binaries}

來自二進制快取嘅 target 係預先構建嘅二進制文件，測試執行只有喺該二進制文件連同覆蓋率計數器構建時才能測量其代碼。開啟覆蓋率後，二進制快取會保留你專案自身 target 嘅插樁版本，每個指令都會讀取並預熱該版本：

- **Debug 組態** 使用插樁版本：`tuist cache` 會預熱它，而 `tuist generate` 同 `tuist test` 會讀取它。
- **Release 組態** 始終使用普通版本，所以你交付嘅產品永遠不會包含覆蓋率計數器。
- **外部套件** 始終使用普通版本。Tuist 只測量你儲存庫嘅代碼。

請喺與你測試 job 相同嘅環境中開啟覆蓋率並預熱快取，以便 `tuist test` 能找到插樁二進制文件。當一次執行收集覆蓋率但從快取取得普通二進制文件作為你嘅 target 時，Tuist 會發出警告，且唔會測量佢哋嘅代碼。<.localized_link href="/guides/features/cache/module-cache#code-coverage">模組快取</.localized_link> 詳細記錄咗呢啲版本。

### 跨機器路徑 {#paths-across-machines}

插樁二進制文件會記錄相對於構建時 checkout 目錄嘅原始碼路徑，因此喺 CI 上預熱嘅二進制文件能夠喺任何開發者嘅機器上測量正確嘅文件。

<.localized_link href="/guides/features/cache/xcode-cache">Xcode 快取</.localized_link> 透過前綴映射以相同方式運作，Tuist 預設會喺收集覆蓋率嘅構建中關閉此功能，因為 Xcode 自身嘅覆蓋率報告無法解析映射後嘅路徑。喺 Xcode 27 及更高版本中，當 `enableCaching` 開啟時，`prefixMapping: true` 會保持其啟用狀態，令覆蓋率構建亦能喺唔同 checkout 之間共享編譯結果：

```swift
.options(coverage: .coverage(enabled: true, prefixMapping: true))
```

Tuist 嘅上傳會解析映射路徑，但 Xcode 嘅覆蓋率報告同 `xccov` 可能會遺漏呢啲文件。請參閱 <.localized_link href="/guides/features/cache/xcode-cache#coverage-with-prefix-mapping">帶前綴映射嘅覆蓋率</.localized_link>。

### 跳過嘅測試 {#skipped-tests}

當早期一次成功嘅執行已經用相同雜湊值測試過某個測試 target 時，選擇性測試會跳過該 target。雜湊值涵蓋 target 嘅原始碼、其測試同所有依賴項，所以相同雜湊值意味著對相同代碼運行相同測試。Tuist 會重用早期執行為該 target 記錄嘅 [target 層級覆蓋率](#target-level-coverage)。如果當時無記錄（例如因為當時關閉咗覆蓋率，或者執行超過 31 日），就無數據可攜帶，該 commit 會被標記為 **Incomplete**。

選擇性執行亦唔會構建每個文件。對於佢無編譯嘅文件，只要文件自上次完整執行以來無變更，Tuist 就會採用最近一次完整執行中嘅行數據。這就係點解你預設分支上嘅 [完整執行](#full-runs) 如此重要。

你自己使用 `--skip-test-targets` 或 `-skip-testing` 跳過嘅測試唔會被攜帶：如果某次執行跳過咗佢哋，而該 commit 下嘅其他執行亦無運行佢哋，則該 commit 會被標記為 **Incomplete**。被隔離跳過嘅測試完全唔屬於覆蓋率範圍：Tuist 既唔會攜帶佢哋，亦唔會因此將 commit 標記為 **Incomplete**。

### 完整與不完整嘅 commit {#commit-status}

儀表板上每個 commit 都有一個狀態：

| 狀態 | 含義 |
| --- | --- |
| 進行中 | 已有執行報告咗覆蓋率，但尚未為該 commit 運行 `tuist coverage complete`。 |
| 完整 | 該 commit 方案嘅所有測試均已運行或被攜帶。 |
| 不完整 | 部分覆蓋率無法確定，因此數值僅為下限。 |
| 未測量 | 無任何執行為該 commit 報告覆蓋率。 |

分支趨勢僅包含完整嘅 commit。當出現以下情況時，commit 會被視為不完整：

- 選擇性測試跳過咗一個無法攜帶嘅 target：早期執行無為其記錄覆蓋率、選擇性執行無構建嘅文件自上次完整執行以來發生咗變更，或者 commit 更改咗影響所有 target 嘅文件，例如 `Package.resolved`、`Project.swift` 或 `.xcconfig`。
- 某次執行使用 `--skip-test-targets` 或 `-skip-testing` 跳過咗測試，且該 commit 下嘅其他執行亦無運行佢哋。
- 某次執行從二進制快取中取得普通二進制文件作為你嘅 target。
- 某方案嘅每次執行都使用 `-only-testing` 進行咗縮減。
- 某方案嘅覆蓋率僅來自帶有未提交更改嘅 checkout 上嘅 CI 執行。

## 性能影響 {#performance-impact}

收集覆蓋率會增加開銷，主要係喺測試完成後，Xcode 寫入覆蓋率報告同 Tuist 導出覆蓋率數據嘅時候。構建同運行測試嘅時間與無覆蓋率時大致相同。插樁構建亦會佔用更多磁盤空間，包括 DerivedData 同 Debug 二進制快取。Release 構建同歸檔不受影響。

## 限制 {#limitations}

### 收集覆蓋率方案嘅 Release 構建 {#release-builds}

當方案嘅測試動作收集覆蓋率時，Xcode 亦會對 `xcodebuild build` 為該方案從原始碼編譯嘅 target 進行插樁，適用於任何組態，包括 Release。`xcodebuild archive` 會忽略此設定，所以歸檔永遠唔會插樁。請分發歸檔，或者從帶有 `.options(coverage: false)` 嘅方案構建 Release 產品。

### 其他覆蓋率工具 {#other-coverage-tools}

`-enableCodeCoverage YES` 僅決定執行是否收集覆蓋率，如同喺 Xcode 中一樣。它並唔會讓 Tuist 從快取中讀取插樁二進制文件，所以請改用 `Tuist.swift` 選項或 `TUIST_COVERAGE_ENABLED`。

若要餵給其他覆蓋率工具，請讓 `tuist test` 將每次執行嘅覆蓋率寫為 LCOV 格式。這與 Tuist 上傳嘅覆蓋率相同，包含相對於儲存庫嘅路徑以及來自二進制快取嘅代碼：

```sh
tuist test --coverage-output-path coverage
```

每次執行會寫入 `coverage/<result bundle name>.lcov`。使用 `lcov -a` 合併分片執行嘅文件。此選項需要開啟覆蓋率上傳。

Xcode 自身嘅覆蓋率報告及讀取它嘅工具，僅包含 Xcode 在該次執行中構建嘅 target，絕不包含來自二進制快取嘅代碼。Tuist 嘅上傳則兩者皆測量。如果你希望喺 Xcode 報告中看到某個 target 嘅覆蓋率，請生成專案時讓該 target 從原始碼構建：`tuist generate MyTarget` 會保留 `MyTarget` 為原始碼，並從快取中獲取其餘部分。

## 查詢覆蓋率 {#querying}

`tuist coverage` 指令會讀取儀表板顯示嘅內容。如果無 `--commit`，佢哋會讀取 `--branch` 或你預設分支上最新嘅完整 commit：

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

佢哋全部接受 `--json` 以便腳本化處理。代理亦可通過 <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol server</.localized_link> 獲取相同數據。
