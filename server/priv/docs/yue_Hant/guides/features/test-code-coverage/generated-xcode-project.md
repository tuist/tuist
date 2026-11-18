---
{
  "title": "生成的 Xcode 專案",
  "titleTemplate": ":title · 程式碼覆蓋率 · 功能 · 指南 · Tuist",
  "description": "按檔案及每次提交，測量由 Tuist 生成的 Xcode 專案之程式碼覆蓋率，包括被二進制快取與選擇性測試跳過的程式碼。"
}
---
# 生成嘅 Xcode 專案 {#generated-xcode-project-code-coverage}

代碼覆蓋率告訴你測試執行咗你代碼嘅邊啲行。Tuist 會上傳每次 `tuist test` 執行嘅行覆蓋率，並將一個 commit 嘅所有執行合併成一個數字，涵蓋整個專案、每個 target 同每個檔案。儀表板嘅 **代碼覆蓋率** 頁面會按 commit 顯示，並作為每個 branch 嘅趨勢呈現。

<!-- @snippet: ./_xcode-requirements -->

當 Tuist 跳過部分工作時，數字仍然準確。你從 <.localized_link href="/guides/features/cache/module-cache">二進制緩存</.localized_link> 獲取嘅 target 係帶住覆蓋率計數器構建嘅，所以佢哋嘅代碼會好似從源代碼構建嘅代碼一樣被測量。而當 <.localized_link href="/guides/features/selective-testing/generated-xcode-project">選擇性測試</.localized_link> 跳過某個測試 target 時，該 target 會保留之前執行中嘅覆蓋率，因為 Tuist 會在每次執行時記錄 [target 層級覆蓋率](#target-level-coverage)。

## 設定 {#setup}

### 開啟覆蓋率 {#turn-coverage-on}

喺你 `Tuist.swift` 嘅生成選項中開啟覆蓋率，並開啟預設關閉嘅覆蓋率上傳功能：

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

開啟生成選項後：

- Tuist 生成嘅每個 scheme 嘅測試動作都會收集覆蓋率，你定義嘅每個未設定 `coverage` 嘅 scheme 嘅測試動作亦然。設有 `.options(coverage: false)` 或 `.options(coverage: true)` 嘅 scheme 會保留其值。測試計劃自行決定覆蓋率：對於 Tuist 生成嘅測試計劃，請向 `.testPlans(_:coverage:)` 傳遞 `coverage: true`。
- 你專案自身嘅 target 會以 Debug 配置下帶覆蓋率計數器嘅形式讀取並預熱到二進制緩存中。參閱 [運作原理](#instrumented-binaries)。

`TUIST_COVERAGE_ENABLED` 同 `TUIST_COVERAGE_UPLOAD` 環境變數（`1` 或 `0`）優先於 `enabled` 同 `upload`。請為整個環境（例如 CI 工作流程）設定，而唔係為單一命令設定，以便預熱緩存嘅命令同讀取緩存嘅命令保持一致。

> [!IMPORTANT] KEEP THE VALUE THE SAME EVERYWHERE
> 生成選項會改變你專案 target 嘅緩存金鑰同其測試 target 嘅選擇性測試哈希值。喺共享緩存嘅每部機器上使用相同嘅值，唔好從環境衍生（例如從 `Environment.isCI`）。關閉覆蓋率嘅執行唔會重用開啟覆蓋率執行嘅二進制文件或選擇性測試結果。

### 排除 Scheme {#leave-schemes-out}

有些測試套件唔應該包含喺你嘅覆蓋率中。例如，從另一個進程驅動你嘅應用程式或 CLI 嘅驗收測試或端到端測試，會執行覆蓋率無法看到嘅代碼，收集覆蓋率只會令佢哋變慢。喺佢哋 scheme 嘅測試動作中關閉覆蓋率：

```swift
.scheme(
    name: "AcceptanceTests",
    testAction: .targets(
        ["AcceptanceTests"],
        options: .options(coverage: false)
    )
)
```

無論 `Tuist.swift` 選項或 `TUIST_COVERAGE_ENABLED` 點樣設定，該 scheme 都會保持關閉覆蓋率，且其執行唔會計入 commit 嘅覆蓋率。覆蓋率係按 scheme 收集嘅，所以要排除某個測試 target，請將其移至獨立嘅 scheme。

### 運行你嘅測試 {#run-your-tests}

照常使用 `tuist test` 運行你嘅測試：

```sh
tuist test
```

Tuist 會上傳執行收集到嘅覆蓋率以及測試結果。這包括 <.localized_link href="/guides/features/test-sharding/generated-xcode-project">分片執行</.localized_link> 同使用 `--without-building` 喺另一個 job 中構建產品進行測試嘅執行。要防止 Tuist 記錄某次執行嘅覆蓋率（例如喺運行來自 fork 嘅 pull request 嘅 job 中），請設定 `TUIST_COVERAGE_UPLOAD=0`。

### 喺 CI 上完成每個 Commit {#complete-each-commit}

一個 commit 嘅覆蓋率通常來自多個 job：每個 scheme、每個分片或每個平台各一個。Tuist 無法知道最後一個 job 何時報告完成，所以你需要告訴佢。當一個 commit 嘅所有測試 job 都完成後，喺依賴所有佢哋嘅 job 中運行以下命令：

```sh
tuist coverage complete
```

該命令會從 checkout 或你嘅 CI 提供商讀取 commit；傳遞 `--commit <sha>` 以指定另一個 commit。喺 commit 完成之前，其覆蓋率會顯示為 **進行中**，且唔會計入其 branch 嘅趨勢。

### 喺你嘅預設 Branch 上運行完整套件 {#full-runs}

> [!IMPORTANT] SET UP A FULL RUN
> 只有當有早期執行可以承接被跳過嘅 target 時，選擇性測試才能保持 commit 覆蓋率完整。喺你嘅預設 branch 上安排一次不帶選擇性測試嘅完整測試執行：
>
> ```sh
> tuist test --no-selective-testing
> ```
>
> 理想情況下每次 merge 都運行一次。對於變更較少嘅倉庫，每日或每週運行一次可能已足夠。記錄嘅覆蓋率喺 31 天後過期，所以運行頻率應高於此。

承接嘅覆蓋率依賴完整執行。佢哋會喺過期前刷新每個 target 嘅記錄覆蓋率，並為 Tuist 提供選擇性執行未構建文件嘅最新狀態。倉庫喺兩次完整執行之間變更越多，選擇性執行就越常發現自上次以來已變更嘅文件，導致其 commit 覆蓋率顯示為 **不完整**。

## Target 層級覆蓋率 {#target-level-coverage}

一次執行嘅覆蓋率說明整個執行執行咗乜，而唔係每個測試 target 執行咗乜。當選擇性測試跳過某個 target 時，Tuist 需要知道該 target 喺早期執行中執行咗乜，以便承接其覆蓋率。

因此，喺每次執行時，Tuist 亦會記錄每個測試 target 執行咗邊啲文件同行。佢從 Xcode 為每個測試進程寫入嘅覆蓋率中讀取這些數據，所以無需額外連結或配置。這僅喺 macOS 同 iOS 模擬器上記錄，設備上則否。UI 測試唔會記錄佢哋驅動嘅應用程式嘅任何信息，因為應用程式代碼喺自己嘅進程中運行。

## 運作原理 {#how-it-works}

### 插樁二進制文件 {#instrumented-binaries}

來自二進制緩存嘅 target 係預構建嘅二進制文件，只有當二進制文件係帶住覆蓋率計數器構建時，測試執行才能測量其代碼。開啟覆蓋率後，二進制緩存會保留你專案自身 target 嘅插樁版本，每個命令都會讀取並預熱該版本：

- **Debug 配置** 使用插樁版本：`tuist cache` 預熱佢，而 `tuist generate` 同 `tuist test` 讀取佢。
- **Release 配置** 始終使用普通版本，所以你發布嘅產品永遠唔會帶有覆蓋率計數器。
- **外部套件** 始終使用普通版本。Tuist 只測量你倉庫嘅代碼。

喺與你測試 job 相同嘅環境中開啟覆蓋率預熱緩存，以便 `tuist test` 能找到插樁二進制文件。當一次執行收集覆蓋率但從緩存中獲取嘅係普通二進制文件時，Tuist 會發出警告，且其代碼唔會被測量。<.localized_link href="/guides/features/cache/module-cache#code-coverage">模塊緩存</.localized_link> 詳細記錄咗這些版本。

### 跨機器路徑 {#paths-across-machines}

插樁二進制文件會記錄相對於構建時 checkout 嘅源路徑，因此喺 CI 上預熱嘅二進制文件能喺任何開發者嘅機器上測量正確嘅文件。

<.localized_link href="/guides/features/cache/xcode-cache">Xcode 緩存</.localized_link> 透過前綴映射以相同方式運作，Tuist 預設會喺收集覆蓋率嘅構建中關閉此功能，因為 Xcode 自身嘅覆蓋率報告無法解析映射後嘅路徑。喺 Xcode 27 及更高版本中，開啟 `enableCaching` 後，`prefixMapping: true` 會保持其開啟狀態，令覆蓋率構建亦能跨 checkout 共享編譯結果：

```swift
.options(coverage: .coverage(enabled: true, prefixMapping: true))
```

Tuist 嘅上傳會解析映射路徑，但 Xcode 嘅覆蓋率報告同 `xccov` 可能會遺漏這些文件。請參閱 <.localized_link href="/guides/features/cache/xcode-cache#coverage-with-prefix-mapping">帶前綴映射嘅覆蓋率</.localized_link>。

### 跳過嘅測試 {#skipped-tests}

當早期一次通過嘅執行已經用相同哈希測試咗某個測試 target 時，選擇性測試會跳過該 target。哈希涵蓋 target 嘅源代碼、其測試同所有依賴項，所以相同哈希意味著對相同代碼進行相同測試。Tuist 會重用早期執行為該 target 記錄嘅 [target 層級覆蓋率](#target-level-coverage)。如果當時無記錄（例如因為當時關閉咗覆蓋率或執行超過 31 日），則無數據可承接，該 commit 會被標記為 **不完整**。

選擇性執行亦唔會構建每個文件。對於佢未編譯嘅文件，只要文件自上次完整執行以來無變更，Tuist 就會從最近嘅早期完整執行中提取行數據。這就係點解你默認分支上嘅 [完整執行](#full-runs) 如此重要。

你自己使用 `--skip-test-targets` 或 `-skip-testing` 跳過嘅測試唔會被承接：如果某次執行跳過咗它們，且該 commit 無其他執行運行它們，則該 commit 會被標記為 **不完整**。被隔離跳過嘅測試完全唔屬於覆蓋率範圍：Tuist 既唔會承接它們，亦唔會因此將 commit 標記為 **不完整**。

### 完整與不完整嘅 Commit {#commit-status}

儀表板上每個 commit 都有一個狀態：

| 狀態 | 含義 |
| --- | --- |
| 進行中 | 已有執行報告咗覆蓋率，但 `tuist coverage complete` 尚未針對該 commit 運行。 |
| 完整 | 該 commit 方案嘅所有測試均已運行或被承接。 |
| 不完整 | 部分覆蓋率無法確定，因此數值僅為下限。 |
| 未測量 | 無執行報告該 commit 嘅覆蓋率。 |

分支趨勢僅包含完整嘅 commit。例如，在以下情況下 commit 會被視為不完整：

- 選擇性測試跳過咗一個無法承接嘅 target：早期執行無記錄其覆蓋率、選擇性執行未構建嘅文件自上次完整執行以來發生咗變更，或者 commit 更改咗影響所有 target 嘅文件，例如 `Package.resolved`、`Project.swift` 或 `.xcconfig`。
- 某次執行使用 `--skip-test-targets` 或 `-skip-testing` 跳過咗測試，且該 commit 無其他執行運行它們。
- 某次執行從二進制緩存中獲取咗你嘅 target 作為普通二進制文件。
- 方案嘅每次執行都使用 `-only-testing` 進行咗縮減。
- 方案嘅覆蓋率僅來自帶有未提交更改嘅 checkout 上嘅 CI 執行。

## 性能影響 {#performance-impact}

收集覆蓋率會增加開銷，主要係喺測試完成後，Xcode 寫入覆蓋率報告同 Tuist 導出覆蓋率嘅時候。構建和運行測試嘅時間與無覆蓋率時差不多。插樁構建亦會佔用更多磁盤空間，包括 DerivedData 同 Debug 二進制緩存。Release 構建同歸檔不受影響。

## 限制 {#limitations}

### 收集覆蓋率方案嘅 Release 構建 {#release-builds}

當方案嘅測試動作收集覆蓋率時，Xcode 亦會對 `xcodebuild build` 為該方案從源代碼編譯嘅 target 進行插樁，無論係邊種配置（包括 Release）。`xcodebuild archive` 會忽略此設置，因此歸檔永遠唔會進行插樁。請分發歸檔，或使用帶有 `.options(coverage: false)` 嘅方案構建 Release 產品。

### 其他覆蓋率工具 {#other-coverage-tools}

`-enableCodeCoverage YES` 僅決定執行是否收集覆蓋率（如同 Xcode）。它唔會讓 Tuist 從緩存中讀取插樁二進制文件，因此請改用 `Tuist.swift` 選項或 `TUIST_COVERAGE_ENABLED`。

若要為其他覆蓋率工具提供數據，請讓 `tuist test` 將每次執行嘅覆蓋率寫入為 LCOV 格式。這與 Tuist 上傳嘅覆蓋率相同，包含相對於倉庫嘅路徑以及來自二進制緩存嘅代碼：

```sh
tuist test --coverage-output-path coverage
```

每次執行會寫入 `coverage/<result bundle name>.lcov`。使用 `lcov -a` 合併分片執行嘅文件。此選項需要開啟覆蓋率上傳。

Xcode 自身嘅覆蓋率報告及讀取它嘅工具，僅包含 Xcode 在該次執行中構建嘅 target，絕不包含來自二進制緩存嘅代碼。Tuist 嘅上傳會測量兩者。如果你希望喺 Xcode 報告中看到某個 target 嘅覆蓋率，請生成項目時讓該 target 從源代碼構建：`tuist generate MyTarget` 會將 `MyTarget` 保留為源代碼，並從緩存中獲取其餘部分。

## 查詢覆蓋率 {#querying}

`tuist coverage` 命令會讀取儀表板顯示嘅內容。如果無 `--commit`，它們會讀取 `--branch` 或你默認分支嘅最新完整 commit：

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

所有命令都接受 `--json` 以便腳本化處理。代理亦可通過 <.localized_link href="/guides/features/agentic-coding/mcp">模型上下文協議服務器</.localized_link> 訪問相同數據。
