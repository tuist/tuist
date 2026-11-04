---
{
  "title": "生成的 Xcode 專案",
  "titleTemplate": ":title · 程式碼涵蓋率 · 功能 · 指南 · Tuist",
  "description": "按檔案及提交記錄，測量 Tuist 生成的 Xcode 專案之程式碼涵蓋率，包括被二進位快取與選擇性測試跳過的程式碼。"
}
---
# 已生成嘅 Xcode 專案 {#generated-xcode-project-code-coverage}

> [!NOTE] EARLY ACCESS
> Xcode 專案嘅代碼覆蓋率功能處於早期存取階段。[聯絡我哋](mailto:contact@tuist.dev)為你嘅帳戶開啟。在此之前，Tuist 唔會儲存你測試執行所上傳嘅覆蓋率數據。

代碼覆蓋率會告訴你測試執行咗代碼中嘅邊啲行。Tuist 會上傳每次 `tuist test` 執行嘅行覆蓋率，並將同一個提交（commit）嘅多次執行合併成一個數值，涵蓋整個專案、每個目標（target）同每個檔案。儀表板嘅 **代碼覆蓋率** 頁面會按提交顯示，並展示每個分支嘅趨勢。

當 Tuist 跳過部分工作時，數值依然準確。來自 <.localized_link href="/guides/features/cache/module-cache">二進制緩存</.localized_link> 嘅目標係連同覆蓋率計數器一齊構建嘅，所以佢哋嘅代碼會好似從源代碼構建嘅代碼一樣被測量。而當 <.localized_link href="/guides/features/selective-testing/generated-xcode-project">選擇性測試</.localized_link> 跳過某個測試目標時，該目標會保留之前執行中已有嘅覆蓋率，因為 Tuist 會在每次執行時記錄 [目標層級覆蓋率](#target-level-coverage)。

## 設定 {#setup}

### 開啟覆蓋率 {#turn-coverage-on}

喺你嘅 `Tuist.swift` 生成選項中開啟覆蓋率，並啟用覆蓋率上傳功能（預設係關閉嘅）：

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

- Tuist 生成嘅每個 scheme 嘅測試動作都會收集覆蓋率，你自己定義且未設定 `coverage` 嘅 scheme 測試動作亦然。設定咗 `.options(coverage: false)` 或 `.options(coverage: true)` 嘅 scheme 會保持其原有值。測試計劃（Test plans）自行決定覆蓋率：對於 Tuist 生成嘅測試計劃，請向 `.testPlans(_:coverage:)` 傳遞 `coverage: true`。
- 你專案自身嘅目標會以 Debug 配置下嘅覆蓋率計數器讀取並預熱到二進制緩存中。詳情請見 [運作原理](#instrumented-binaries)。

`TUIST_COVERAGE_ENABLED` 同 `TUIST_COVERAGE_UPLOAD` 環境變量（`1` 或 `0`）嘅優先級高於 `enabled` 同 `upload`。請為整個環境（例如 CI 工作流程）設定，而唔係為單一指令設定，以便預熱緩存同讀取緩存嘅指令保持一致。

> [!IMPORTANT] KEEP THE VALUE THE SAME EVERYWHERE
> 生成選項會改變你專案目標嘅緩存金鑰（cache keys）同測試目標嘅選擇性測試哈希值。喺所有共享緩存嘅機器上使用相同嘅值，唔好從環境中衍生（例如從 `Environment.isCI`）。關閉覆蓋率嘅執行唔會重用開啟覆蓋率執行所產生嘅二進制文件或選擇性測試結果。

### 排除 Scheme {#leave-schemes-out}

有些測試套件唔應該包含喺你嘅覆蓋率統計中。例如，從另一個進程驅動你嘅應用程式或 CLI 嘅驗收測試或端到端測試，會執行覆蓋率工具無法看到嘅代碼，收集這些數據只會令測試變慢。請喺佢哋 scheme 嘅測試動作中關閉覆蓋率：

```swift
.scheme(
    name: "AcceptanceTests",
    testAction: .targets(
        ["AcceptanceTests"],
        options: .options(coverage: false)
    )
)
```

無論 `Tuist.swift` 選項或 `TUIST_COVERAGE_ENABLED` 點樣設定，該 scheme 都會保持覆蓋率關閉，其執行結果亦唔會計入提交嘅覆蓋率。覆蓋率係按 scheme 收集嘅，所以如果要排除某個測試目標，請將佢移到獨立嘅 scheme 中。

### 執行測試 {#run-your-tests}

照常使用 `tuist test` 執行你嘅測試：

```sh
tuist test
```

Tuist 會上傳執行期間收集嘅覆蓋率連同測試結果。這包括 <.localized_link href="/guides/features/test-sharding/generated-xcode-project">分片執行</.localized_link> 以及使用 `--without-building` 喺另一個 job 中構建產品並進行測試嘅執行。如果想讓某次執行嘅覆蓋率唔上傳到 Tuist（例如喺運行來自 fork 嘅 pull request 嘅 job 中），請設定 `TUIST_COVERAGE_UPLOAD=0`。

### 喺 CI 上完成每個提交 {#complete-each-commit}

一個提交嘅覆蓋率數據通常來自多個 job：每個 scheme、每個分片或每個平台各一個。Tuist 無法判斷最後一個 job 何時匯報完畢，所以需要你去通知。當一個提交嘅所有測試 job 都完成後，請喺一個依賴晒所有呢些 job 嘅 job 中運行以下指令：

```sh
tuist coverage complete
```

該指令會從 checkout 或你嘅 CI 提供者處讀取提交資訊；傳遞 `--commit <sha>` 可以指定另一個提交。喺提交標記為完成之前，其覆蓋率會顯示為 **進行中**，且唔會計入該分支嘅趨勢。

### 喺你嘅默認分支上運行完整套件 {#full-runs}

> [!IMPORTANT] SET UP A FULL RUN
> 只有當有早前嘅執行來承接被跳過嘅目標時，選擇性測試才能保持提交嘅覆蓋率完整。請喺你嘅默認分支上安排一次不包含選擇性測試嘅完整測試執行：
>
> ```sh
> tuist test --no-selective-testing
> ```
>
> 理想情況下，每次合併都運行一次。對於變更較少嘅倉庫，每日或每週運行一次可能已足夠。記錄嘅覆蓋率數據會喺 90 天後過期，所以運行頻率應高於此。

承接嘅覆蓋率數據依賴於完整執行。完整執行會喺覆蓋率過期前刷新每個目標嘅記錄數據，並為 Tuist 提供選擇性執行未構建文件嘅最新狀態。倉庫喺兩次完整執行之間變更越多，選擇性執行就越容易發現自上次以來已變更嘅文件，導致該提交嘅覆蓋率顯示為 **不完整**。

## 目標層級覆蓋率 {#target-level-coverage}

一次執行嘅覆蓋率反映咗整個執行過程執行咗乜嘢，而唔係每個測試目標分別執行咗乜嘢。當選擇性測試跳過某個目標時，Tuist 需要知道該目標喺早前執行中執行咗乜嘢，以便承接其覆蓋率數據。

因此，喺每次執行時，Tuist 亦會記錄每個測試目標執行咗邊啲文件同行。數據來自 Xcode 為每個測試進程寫入嘅覆蓋率報告，無需額外連結或配置。數據僅喺 macOS 同 iOS 模擬器上記錄，設備上唔會記錄。UI 測試唔會記錄佢所驅動應用程式嘅任何信息，因為應用程式代碼喺獨立進程中運行。

## 運作原理 {#how-it-works}

### 插樁二進制文件 {#instrumented-binaries}

來自二進制緩存嘅目標係預先構建嘅二進制文件，測試執行只有喺該二進制文件係連同覆蓋率計數器構建嘅情況下才能測量其代碼。開啟覆蓋率後，二進制緩存會保存你專案自身目標嘅插樁版本，所有指令都會讀取並預熱該版本：

- **Debug 配置** 使用插樁版本：`tuist cache` 負責預熱，而 `tuist generate` 同 `tuist test` 負責讀取。
- **Release 配置** 始終使用普通版本，所以你發布嘅產品永遠唔會包含覆蓋率計數器。
- **外部套件** 始終使用普通版本。Tuist 只測量你倉庫中嘅代碼。

請喺與你測試 job 相同嘅環境中開啟覆蓋率並預熱緩存，以便 `tuist test` 能找到插樁二進制文件。如果一次執行收集咗覆蓋率，但從緩存中獲取到嘅係普通二進制文件，Tuist 會發出警告，且該代碼唔會被測量。<.localized_link href="/guides/features/cache/module-cache#code-coverage">模組緩存</.localized_link> 詳細記錄咗這些版本。

### 跨機器路徑 {#paths-across-machines}

插樁二進制文件會記錄相對於構建時 checkout 目錄嘅源代碼路徑，因此喺 CI 上預熱嘅二進制文件能夠喺任何開發者嘅機器上正確測量文件。

<.localized_link href="/guides/features/cache/xcode-cache">Xcode 緩存</.localized_link> 透過路徑前綴映射以相同方式運作。Tuist 預設會喺收集覆蓋率嘅構建中關閉此功能，因為 Xcode 自身嘅覆蓋率報告無法解析映射後嘅路徑。喺 Xcode 27 及更高版本中，開啟 `enableCaching` 後，`prefixMapping: true` 會保持其啟用狀態，令覆蓋率構建亦能跨 checkout 共享編譯結果：

```swift
.options(coverage: .coverage(enabled: true, prefixMapping: true))
```

Tuist 嘅上傳會解析映射後嘅路徑，但 Xcode 嘅覆蓋率報告同 `xccov` 可能會遺漏這些文件。請參閱 <.localized_link href="/guides/features/cache/xcode-cache#coverage-with-prefix-mapping">帶前綴映射嘅覆蓋率</.localized_link>。

### 跳過嘅測試 {#skipped-tests}

當早前一次成功嘅執行已使用相同哈希值測試咗某個測試目標時，選擇性測試會跳過該目標。哈希值涵蓋目標嘅源代碼、其測試及所有依賴項，因此相同哈希值意味著對相同代碼運行相同測試。Tuist 會重用早前執行為該目標記錄嘅 [目標層級覆蓋率](#target-level-coverage)。如果當時無記錄任何數據（例如因為當時覆蓋率已關閉，或該執行超過 90 日），則無數據可承接，該 commit 會被標記為 **不完整**。

選擇性執行亦唔會構建每個文件。對於佢未編譯嘅文件，只要文件自上次完整執行以來未發生變化，Tuist 就會取自最近一次完整執行嘅行數據。這就係點解你默認分支上嘅 [完整執行](#full-runs) 如此重要。

你自己使用 `--skip-test-targets` 或 `-skip-testing` 跳過嘅測試唔會被承接：如果某次執行跳過咗它們，且該 commit 嘅其他執行亦無運行它們，則該 commit 會被標記為 **不完整**。被隔離機制跳過嘅測試完全唔屬於覆蓋率範圍：Tuist 既唔會承接它們，亦唔會因此將 commit 標記為 **不完整**。

### 完整與不完整嘅 commit {#commit-status}

儀表板上每個 commit 都有一個狀態：

| 狀態 | 含義 |
| --- | --- |
| 進行中 | 已有執行報告咗覆蓋率，但尚未為該 commit 運行 `tuist coverage complete`。 |
| 完整 | 該 commit 方案中嘅每個測試均已運行或被承接。 |
| 不完整 | 部分覆蓋率無法確定，因此該數值僅為下限。 |
| 未測量 | 無任何執行為該 commit 報告覆蓋率。 |

分支趨勢僅包含完整嘅 commit。例如，以下情況會導致 commit 不完整：

- 選擇性測試跳過咗一個無法承接嘅目標：早前執行無記錄其覆蓋率、選擇性執行未構建嘅文件自上次完整執行以來發生咗變化，或者 commit 更改咗影響所有目標嘅文件，例如 `Package.resolved`、`Project.swift` 或 `.xcconfig`。
- 某次執行使用 `--skip-test-targets` 或 `-skip-testing` 跳過咗測試，且該 commit 嘅其他執行亦無運行它們。
- 某次執行從二進制緩存中獲取咗普通二進制文件作為你嘅目標。
- 某方案嘅每次執行都通過 `-only-testing` 縮小咗範圍。
- 某方案嘅覆蓋率僅來自於含有未提交更改嘅 checkout 上嘅 CI 執行。

## 性能影響 {#performance-impact}

收集覆蓋率會增加開銷，主要發生喺測試完成後，即 Xcode 寫入覆蓋率報告同 Tuist 導出覆蓋率數據期間。構建和運行測試嘅時間與未開啟覆蓋率時大致相同。插樁構建亦會佔用更多磁盤空間，包括 DerivedData 同 Debug 二進制緩存。Release 構建同歸檔文件不受影響。

## 限制 {#limitations}

### 收集覆蓋率方案嘅 Release 構建 {#release-builds}

當方案嘅測試動作收集覆蓋率時，Xcode 亦會對 `xcodebuild build` 為該方案從源代碼編譯嘅目標進行插樁，適用於任何配置，包括 Release。`xcodebuild archive` 會忽略此設置，因此歸檔文件永遠唔會被插樁。請分發歸檔文件，或使用帶有 `.options(coverage: false)` 嘅方案來構建 Release 產品。

### 其他覆蓋率工具 {#other-coverage-tools}

`-enableCodeCoverage YES` 僅決定執行是否收集覆蓋率，如同喺 Xcode 中一樣。它並唔會讓 Tuist 從緩存中讀取插樁二進制文件，因此請改用 `Tuist.swift` 選項或 `TUIST_COVERAGE_ENABLED`。

若要為其他覆蓋率工具提供數據，請讓 `tuist test` 將每次執行嘅覆蓋率寫入為 LCOV 格式。這與 Tuist 上傳嘅覆蓋率相同，包含相對於倉庫嘅路徑以及來自二進制緩存嘅代碼：

```sh
tuist test --coverage-output-path coverage
```

每次執行會寫入 `coverage/<result bundle name>.lcov`。使用 `lcov -a` 合併分片執行嘅文件。此選項需要開啟覆蓋率上傳。

Xcode 自身嘅覆蓋率報告及讀取該報告嘅工具，僅包含 Xcode 在該次執行中構建嘅目標，絕不包含來自二進制緩存嘅代碼。Tuist 嘅上傳會同時測量兩者。如果你希望喺 Xcode 報告中看到某個目標嘅覆蓋率，請生成項目時讓該目標從源代碼構建：`tuist generate MyTarget` 會保持 `MyTarget` 為源代碼構建，並從緩存中獲取其餘部分。

## 查詢覆蓋率 {#querying}

`tuist coverage` 指令會讀取儀表板顯示嘅內容。如果不指定 `--commit`，它們會讀取 `--branch` 或你默認分支上最新嘅完整 commit：

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
```

所有指令均接受 `--json` 以便腳本化處理。代理亦可通過 <.localized_link href="/guides/features/agentic-coding/mcp">模型上下文協議服務器</.localized_link> 獲取相同數據。
