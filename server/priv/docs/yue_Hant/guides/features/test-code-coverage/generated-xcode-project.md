---
{
  "title": "生成的 Xcode 專案",
  "titleTemplate": ":title · 程式碼涵蓋率 · 功能 · 指南 · Tuist",
  "description": "測量由 Tuist 生成的 Xcode 專案中，每個檔案和每次提交的程式碼涵蓋率，包括被二進制快取和選擇性測試跳過的程式碼。"
}
---
# 生成嘅 Xcode 專案 {#generated-xcode-project-code-coverage}

代碼覆蓋率會告訴你測試執行咗你代碼嘅邊啲行。Tuist 會上傳每次 `tuist test` 執行嘅行覆蓋率，並將一個 commit 嘅所有執行合併成一個數字，涵蓋整個專案、每個 target 同每個檔案。儀表板嘅 **代碼覆蓋率** 頁面會按 commit 顯示，並展示每個分支嘅趨勢。

<!-- @snippet: ./_xcode-requirements -->

當 Tuist 跳過部分工作時，數字仍然準確。你從 <.localized_link href="/guides/features/cache/module-cache">二進制緩存</.localized_link> 取得嘅 target 係連同覆蓋率計數器一齊編譯嘅，所以佢哋嘅代碼會好似從源碼編譯嘅代碼一樣被測量。而當 <.localized_link href="/guides/features/selective-testing/generated-xcode-project">選擇性測試</.localized_link> 跳過某個測試 target 時，該 target 會保留之前執行中嘅覆蓋率數據，透過 Tuist 在每次執行時記錄嘅 [target 層級覆蓋率](#target-level-coverage) 來實現。

## 設定 {#setup}

### 開啟覆蓋率 {#turn-coverage-on}

喺你 `Tuist.swift` 嘅生成選項中開啟覆蓋率，並開啟預設為關閉嘅覆蓋率上傳功能：

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

- Tuist 生成嘅每個 scheme 嘅測試動作都會收集覆蓋率，你定義嘅任何未設定 `coverage` 嘅 scheme 嘅測試動作亦然。設有 `.options(coverage: false)` 或 `.options(coverage: true)` 嘅 scheme 會保留其設定值。測試計劃會自行決定覆蓋率：對於 Tuist 生成嘅測試計劃，請將 `coverage: true` 傳遞畀 `.testPlans(_:coverage:)`。
- 你專案自身嘅 target 會在 Debug 配置中以帶覆蓋率計數器嘅形式讀取並預熱至二進制緩存。參閱 [運作原理](#instrumented-binaries)。

`TUIST_COVERAGE_ENABLED` 同 `TUIST_COVERAGE_UPLOAD` 環境變數（`1` 或 `0`）嘅優先級高於 `enabled` 同 `upload`。請為整個環境（例如 CI 工作流程）而非單一指令設定呢啲變數，確保預熱緩存同讀取緩存嘅指令保持一致。

> [!IMPORTANT] KEEP THE VALUE THE SAME EVERYWHERE
> 生成選項會改變你專案 target 嘅緩存鍵值同測試 target 嘅選擇性測試哈希值。喺所有共享緩存嘅機器上使用相同嘅值，唔好從環境中衍生該值（例如從 `Environment.isCI`）。關閉覆蓋率嘅執行無法重用開啟覆蓋率執行所產生嘅二進制文件或選擇性測試結果。

### 排除 Scheme {#leave-schemes-out}

有些測試套件唔應該包含喺你嘅覆蓋率報告中。例如，從另一個進程驅動你嘅應用程式或 CLI 嘅驗收測試或端到端測試，會執行覆蓋率工具無法偵測嘅代碼，收集覆蓋率只會令佢哋變慢。請喺佢哋 scheme 嘅測試動作中關閉覆蓋率：

```swift
.scheme(
    name: "AcceptanceTests",
    testAction: .targets(
        ["AcceptanceTests"],
        options: .options(coverage: false)
    )
)
```

無論 `Tuist.swift` 選項或 `TUIST_COVERAGE_ENABLED` 點設定，該 scheme 都會保持覆蓋率關閉，其執行結果亦不會計入 commit 嘅覆蓋率。覆蓋率係按 scheme 收集嘅，所以要排除某個測試 target，請將其移至獨立嘅 scheme。

### 執行你嘅測試 {#run-your-tests}

照常使用 `tuist test` 執行你嘅測試：

```sh
tuist test
```

Tuist 會上傳執行期間收集嘅覆蓋率數據連同測試結果。這包括 <.localized_link href="/guides/features/test-sharding/generated-xcode-project">分片執行</.localized_link> 同使用 `--without-building` 喺另一個 job 中構建產品嘅測試執行。要防止 Tuist 記錄某次執行嘅覆蓋率（例如喺處理來自 fork 嘅 pull request 嘅 job 中），請設定 `TUIST_COVERAGE_UPLOAD=0`。

### 喺 CI 上完成每個 Commit {#complete-each-commit}

一個 commit 嘅覆蓋率數據通常來自多個 job：每個 scheme、每個分片或每個平台各一個。Tuist 無法判斷最後一個 job 何時匯報完畢，所以需要由你告知。當一個 commit 嘅所有測試 job 完成後，喺依賴晒所有呢啲 job 嘅 job 中執行以下指令：

```sh
tuist coverage complete
```

該指令會從檢出目錄或你嘅 CI 供應商讀取 commit；傳遞 `--commit <sha>` 以指定另一個 commit。喺 commit 標記為完成之前，其覆蓋率會顯示為 **進行中**，且不會納入分支趨勢。

### 喺你嘅預設分支上執行完整測試套件 {#full-runs}

> [!IMPORTANT] SET UP A FULL RUN
> 只有當有先前嘅執行可以承接被跳過嘅 target 時，選擇性測試才能保持 commit 覆蓋率完整。請喺你嘅預設分支上安排一次不包含選擇性測試嘅完整測試執行：
>
> ```sh
> tuist test --no-selective-testing
> ```
>
> 理想情況係每次 merge 都執行一次。對於變更較少嘅倉庫，每日或每週執行一次可能已足夠。記錄嘅覆蓋率數據會喺 90 日後過期，所以執行頻率應高於此。

承接嘅覆蓋率數據依賴完整執行。它們會喺過期前刷新每個 target 嘅記錄覆蓋率，並為 Tuist 提供選擇性執行未構建檔案嘅最新狀態。倉庫喺兩次完整執行之間變更越多，選擇性執行就越常發現自上次以來已變更嘅檔案，導致該 commit 嘅覆蓋率顯示為 **不完整**。

## Target 層級覆蓋率 {#target-level-coverage}

一次執行嘅覆蓋率反映的是整個執行過程執行了乜嘢，而非每個測試 target 各自執行了乜嘢。當選擇性測試跳過某個 target 時，Tuist 需要知道該 target 喺先前執行中執行了乜嘢，以便承接其覆蓋率數據。

因此，喺每次執行時，Tuist 亦會記錄每個測試 target 執行咗邊啲檔案同行。它從 Xcode 為每個測試進程寫入嘅覆蓋率數據中讀取呢啲資訊，所以無需額外連結或配置。這僅喺 macOS 同 iOS 模擬器上記錄，設備上則不會。UI 測試不會記錄佢所驅動應用程式嘅任何數據，因為應用程式代碼喺獨立進程中運行。

## 運作原理 {#how-it-works}

### 插樁二進制文件 {#instrumented-binaries}

來自二進制緩存嘅 target 係預先構建嘅二進制文件，只有當該二進制文件係連同覆蓋率計數器一齊構建時，測試執行才能測量其代碼。開啟覆蓋率後，二進制緩存會保留你專案自身 target 嘅插樁版本，每個指令都會讀取並預熱該版本：

- **Debug 配置** 使用插樁版本：`tuist cache` 負責預熱，而 `tuist generate` 同 `tuist test` 負責讀取。
- **Release 配置** 始終使用普通版本，所以你交付嘅產品永遠唔會包含覆蓋率計數器。
- **外部套件** 始終使用普通版本。Tuist 只測量你倉庫內嘅代碼。

請喺與你測試 job 相同嘅環境中開啟覆蓋率來預熱緩存，確保 `tuist test` 能找到插樁二進制文件。如果一次執行收集了覆蓋率但從緩存中取得嘅係普通二進制文件，Tuist 會發出警告，且該代碼不會被測量。<.localized_link href="/guides/features/cache/module-cache#code-coverage">模塊緩存</.localized_link> 詳細記錄咗呢啲版本嘅差異。

### 跨機器路徑 {#paths-across-machines}

插樁二進制文件會記錄相對於其構建時檢出目錄嘅源碼路徑，因此喺 CI 上預熱嘅二進制文件能喺任何開發者嘅機器上正確測量對應檔案。

<.localized_link href="/guides/features/cache/xcode-cache">Xcode 緩存</.localized_link> 透過路徑前綴映射以相同方式運作。Tuist 預設會喺收集覆蓋率嘅構建中關閉此功能，因為 Xcode 自身嘅覆蓋率報告無法解析映射後嘅路徑。喺 Xcode 27 及更高版本中，開啟 `enableCaching` 時，`prefixMapping: true` 會保持其啟用狀態，令覆蓋率構建亦能跨檢出目錄共享編譯結果：

```swift
.options(coverage: .coverage(enabled: true, prefixMapping: true))
```

Tuist 嘅上傳會解析映射後嘅路徑，但 Xcode 嘅覆蓋率報告同 `xccov` 可能會遺漏呢啲檔案。請參閱 <.localized_link href="/guides/features/cache/xcode-cache#coverage-with-prefix-mapping">帶路徑前綴映射嘅覆蓋率</.localized_link>。

### 跳過嘅測試 {#skipped-tests}

當先前一次通過嘅執行已使用相同哈希值測試咗某個測試 target 時，選擇性測試會跳過該 target。哈希值涵蓋 target 嘅源碼、其測試及所有依賴項，因此相同哈希值意味著對相同代碼運行相同測試。Tuist 會重用先前執行為該 target 記錄嘅 [target 層級覆蓋率](#target-level-coverage)。如果當時無記錄（例如因為當時關閉咗覆蓋率，或該執行超過 90 日），則無數據可承接，該 commit 會被標記為 **不完整**。

選擇性執行亦不會構建每個檔案。對於佢未編譯嘅檔案，只要檔案自上次完整執行以來無變更，Tuist 就會採用最近一次完整執行中嘅行數據。這就係點解你預設分支上嘅 [完整執行](#full-runs) 如此重要。

你自己使用 `--skip-test-targets` 或 `-skip-testing` 跳過嘅測試不會被承接：如果某次 commit 嘅執行遺漏咗呢啲測試，且該 commit 下無其他執行運行過佢哋，則該 commit 會被標記為 **不完整**。被隔離機制跳過嘅測試完全不計入覆蓋率：Tuist 既不會承接佢哋，亦不會因此將 commit 標記為 **不完整**。

### 完整與不完整嘅 commit {#commit-status}

儀表板上每個 commit 都有一個狀態：

| 狀態 | 含義 |
| --- | --- |
| 進行中 | 已有執行匯報咗覆蓋率，但尚未為該 commit 運行 `tuist coverage complete`。 |
| 完整 | 該 commit 方案中嘅每個測試均已運行或被承接。 |
| 不完整 | 部分覆蓋率無法確定，因此該數值僅為下限。 |
| 未測量 | 無任何執行為該 commit 匯報覆蓋率。 |

分支趨勢僅包含完整嘅 commit。例如，喺以下情況中，commit 會被視為不完整：

- 選擇性測試跳過咗一個無法承接嘅 target：先前執行無為其記錄覆蓋率、選擇性執行未構建嘅某個檔案自上次完整執行以來發生咗變更，或者該 commit 變更咗影響所有 target 嘅檔案，例如 `Package.resolved`、`Project.swift` 或 `.xcconfig`。
- 某次執行使用 `--skip-test-targets` 或 `-skip-testing` 跳過咗測試，且該 commit 下無其他執行運行過呢啲測試。
- 某次執行從二進制緩存中取得嘅係普通二進制文件而非插樁版本。
- 某方案嘅每次執行都使用 `-only-testing` 進行咗縮減。
- 某方案嘅覆蓋率僅來自於包含未提交變更嘅檢出目錄上嘅 CI 執行。

## 性能影響 {#performance-impact}

收集覆蓋率會增加額外開銷，主要發生喺測試完成後，即 Xcode 寫入覆蓋率報告同 Tuist 導出覆蓋率數據嘅期間。構建同運行測試嘅時間與未開啟覆蓋率時大致相同。插樁構建亦會佔用更多磁盤空間，包括 DerivedData 同 Debug 二進制緩存。Release 構建同歸檔不受影響。

## 限制 {#limitations}

### 收集覆蓋率方案嘅 Release 構建 {#release-builds}

當方案嘅測試動作收集覆蓋率時，Xcode 亦會對 `xcodebuild build` 為該方案從源碼編譯嘅 target 進行插樁，適用於任何配置（包括 Release）。`xcodebuild archive` 會忽略此設置，因此歸檔永遠不會被插樁。請分發歸檔文件，或使用帶有 `.options(coverage: false)` 嘅方案來構建 Release 產品。

### 其他覆蓋率工具 {#other-coverage-tools}

`-enableCodeCoverage YES` 僅決定執行是否收集覆蓋率，如同喺 Xcode 中一樣。它不會令 Tuist 從緩存中讀取插樁二進制文件，因此請改用 `Tuist.swift` 選項或 `TUIST_COVERAGE_ENABLED`。

若要為其他覆蓋率工具提供數據，可讓 `tuist test` 將每次執行嘅覆蓋率寫入為 LCOV 格式。這與 Tuist 上傳嘅覆蓋率相同，包含相對於倉庫嘅路徑以及來自二進制緩存嘅代碼：

```sh
tuist test --coverage-output-path coverage
```

每次執行會寫入 `coverage/<result bundle name>.lcov`。使用 `lcov -a` 合併分片執行嘅文件。此選項需要開啟覆蓋率上傳。

Xcode 自身嘅覆蓋率報告及讀取該報告嘅工具，僅包含 Xcode 喺該次執行中構建嘅 target，絕不包含來自二進制緩存嘅代碼。Tuist 嘅上傳則兩者皆測量。如果你希望喺 Xcode 報告中看到某個 target 嘅覆蓋率，請生成項目時讓該 target 從源碼構建：`tuist generate MyTarget` 會保持 `MyTarget` 為源碼構建，並從緩存中獲取其餘部分。

## 查詢覆蓋率 {#querying}

`tuist coverage` 指令會讀取儀表板顯示嘅內容。如果無指定 `--commit`，佢哋會讀取 `--branch` 或你預設分支上最新嘅完整 commit：

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
```

所有指令均接受 `--json` 以便腳本化處理。代理亦可透過 <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol 伺服器</.localized_link> 訪問相同數據。
