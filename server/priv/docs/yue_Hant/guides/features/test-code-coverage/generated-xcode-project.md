---
{
  "title": "生成嘅 Xcode 專案",
  "titleTemplate": ":title · 代碼覆蓋率 · 功能 · 指南 · Tuist",
  "description": "測量 Tuist 生成嘅 Xcode 專案中每個檔案同每次提交嘅代碼覆蓋率，包括被二進制緩存同選擇性測試跳過嘅代碼。"
}
---
# 生成的 Xcode 專案 {#generated-xcode-project-code-coverage}

<!-- @snippet: ./_xcode-early-access -->

程式碼涵蓋率會告訴你測試執行了你程式碼中的哪些行。Tuist 會上傳每次 `tuist test` 執行的行涵蓋率，並將一個 commit 的所有執行結果合併為單一數值，適用於整個專案、每個 target 及每個檔案。儀表板的 **程式碼涵蓋率** 頁面會按 commit 顯示此數據，並呈現各分支的趨勢。

當 Tuist 略過部分工作時，該數值仍保持準確。來自 <.localized_link href="/guides/features/cache/module-cache">二進制快取</.localized_link> 的 target 在建置時已加入涵蓋率計數器，因此其程式碼測量方式與從原始碼建置的程式碼相同。而當 <.localized_link href="/guides/features/selective-testing/generated-xcode-project">選擇性測試</.localized_link> 略過某個測試 target 時，該 target 會保留先前執行時的涵蓋率，這是透過 Tuist 在每次執行時記錄的 [target 層級涵蓋率](#target-level-coverage) 來實現。

## 設定 {#setup}

### 開啟涵蓋率 {#turn-coverage-on}

在你的 `Tuist.swift` 生成選項中開啟涵蓋率，並啟用涵蓋率上傳功能（預設為關閉）：

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

啟用生成選項後：

- Tuist 生成的每個 scheme 的測試動作都會收集涵蓋率，你定義且未設定 `coverage` 的 scheme 測試動作亦然。若 scheme 設定為 `.options(coverage: false)` 或 `.options(coverage: true)`，則會保留其設定值。測試計畫可自行決定涵蓋率：對於 Tuist 生成的測試計畫，請將 `coverage: true` 傳遞給 `.testPlans(_:coverage:)`。
- 你專案自身的 target 會在 Debug 組態中以涵蓋率計數器讀取並預熱至二進制快取。詳情請參閱 [運作原理](#instrumented-binaries)。

環境變數 `TUIST_COVERAGE_ENABLED` 和 `TUIST_COVERAGE_UPLOAD`（值為 `1` 或 `0`）的優先級高於 `enabled` 和 `upload`。請為整個環境（例如 CI 工作流程）設定這些變數，而非僅針對單一指令，以確保預熱快取與讀取快取的指令保持一致。

> [!IMPORTANT] KEEP THE VALUE THE SAME EVERYWHERE
> 生成選項會改變你專案 target 的快取金鑰及其測試 target 的選擇性測試雜湊值。在所有共用快取的機器上使用相同的值，切勿從環境變數衍生該值（例如從 `Environment.isCI`）。關閉涵蓋率的執行無法重用開啟涵蓋率執行所產生的二進制檔或選擇性測試結果。

### 排除 Scheme {#leave-schemes-out}

某些測試套件不應納入你的涵蓋率計算。例如，從另一個程序驅動你的應用程式或 CLI 的驗收測試或端到端測試，其所執行的程式碼是涵蓋率工具無法偵測的，收集這些數據只會讓測試變慢。請在該 scheme 的測試動作中關閉涵蓋率：

```swift
.scheme(
    name: "AcceptanceTests",
    testAction: .targets(
        ["AcceptanceTests"],
        options: .options(coverage: false)
    )
)
```

無論 `Tuist.swift` 選項或 `TUIST_COVERAGE_ENABLED` 如何設定，該 scheme 都會保持關閉涵蓋率，且其執行結果不會計入 commit 的涵蓋率。涵蓋率是按 scheme 收集的，因此若要排除某個測試 target，請將其移至獨立的 scheme。

### 執行測試 {#run-your-tests}

像往常一樣使用 `tuist test` 執行測試：

```sh
tuist test
```

Tuist 會上傳執行期間收集的涵蓋率以及測試結果。這包括 <.localized_link href="/guides/features/test-sharding/generated-xcode-project">分片執行</.localized_link> 以及使用 `--without-building` 在另一個 job 中建置產品並進行測試的執行。若要防止 Tuist 記錄某次執行的涵蓋率（例如在執行來自 fork 的 pull request 的 job 中），請設定 `TUIST_COVERAGE_UPLOAD=0`。

### 在 CI 上完成每個 Commit {#complete-each-commit}

一個 commit 的涵蓋率通常來自多個 job：每個 scheme、每個分片或每個平台各一個。Tuist 無法判斷最後一個 job 何時回報完畢，因此需要你明確告知。當一個 commit 的所有測試 job 完成後，請在依賴所有這些 job 的 job 中執行以下指令：

```sh
tuist coverage complete
```

該指令會從 checkout 或你的 CI 提供者讀取 commit；若要指定其他 commit，請傳遞 `--commit <sha>`。在 commit 標記為完成之前，其涵蓋率會顯示為 **進行中**，且不會納入該分支的趨勢計算。

### 在預設分支上執行完整測試套件 {#full-runs}

> [!IMPORTANT] SET UP A FULL RUN
> 只有當存在先前的執行結果可承接被略過的 target 時，選擇性測試才能保持 commit 涵蓋率的完整性。請在你的預設分支上排程執行所有測試，且不啟用選擇性測試：
>
> ```sh
> tuist test --no-selective-testing
> ```
>
> 理想情況是每次合併時執行一次。對於變更較少的儲存庫，每日或每週執行一次可能已足夠。記錄的涵蓋率會在 90 天後過期，因此執行頻率應高於此期限。

承接的涵蓋率依賴完整執行。完整執行會在涵蓋率過期前刷新每個 target 的記錄涵蓋率，並讓 Tuist 掌握選擇性執行未建置檔案的最新狀態。儲存庫在兩次完整執行之間的變更越多，選擇性執行就越常發現自上次以來已變更的檔案，導致該 commit 的涵蓋率顯示為 **不完整**。

## Target 層級涵蓋率 {#target-level-coverage}

單次執行的涵蓋率反映的是整個執行過程的結果，而非每個測試 target 個別執行的結果。當選擇性測試略過某個 target 時，Tuist 需要知道該 target 在先前執行中執行了哪些內容，以便承接其涵蓋率。

因此，在每次執行時，Tuist 也會記錄每個測試 target 執行了哪些檔案和行數。這些數據來自 Xcode 為每個測試進程寫入的涵蓋率報告，無需額外連結或設定。此記錄僅適用於 macOS 和 iOS 模擬器，不適用於實體裝置。UI 測試不會記錄其所驅動應用程式的任何資訊，因為應用程式的程式碼是在獨立的進程中運行。

## 運作原理 {#how-it-works}

### 插樁二進制檔 {#instrumented-binaries}

來自二進制快取的 target 是預先建置的二進制檔，測試執行只有在該二進制檔建置時加入了涵蓋率計數器的情況下，才能測量其程式碼。啟用涵蓋率後，二進制快取會保留你專案自身 target 的插樁版本，且每個指令都會讀取並預熱該版本：

- **Debug 組態** 使用插樁版本：`tuist cache` 負責預熱，而 `tuist generate` 和 `tuist test` 則負責讀取。
- **Release 組態** 始終使用普通版本，因此你發佈的產品永遠不會包含涵蓋率計數器。
- **外部套件** 始終使用普通版本。Tuist 僅測量你儲存庫內的程式碼。

請在與測試 job 相同的環境中開啟涵蓋率並預熱快取，以便 `tuist test` 能找到插樁二進制檔。當執行收集了涵蓋率，但從快取中取得的 target 是普通二進制檔時，Tuist 會發出警告，且這些程式碼不會被測量。<.localized_link href="/guides/features/cache/module-cache#code-coverage">模組快取</.localized_link> 詳細記錄了這些版本差異。

### 跨機器的路徑 {#paths-across-machines}

插樁二進制檔會記錄相對於其建置時所在 checkout 的原始碼路徑，因此在 CI 上預熱的二進制檔能在任何開發者的機器上正確測量相應檔案。

<.localized_link href="/guides/features/cache/xcode-cache">Xcode 快取</.localized_link> 透過路徑前綴映射以相同方式運作。Tuist 預設會在收集涵蓋率的建置中關閉此功能，因為 Xcode 自身的涵蓋率報告無法解析映射後的路徑。在 Xcode 27 及更高版本中，啟用 `enableCaching` 後，`prefixMapping: true` 會保持其開啟狀態，因此涵蓋率建置也能在不同 checkout 之間共享編譯結果：

```swift
.options(coverage: .coverage(enabled: true, prefixMapping: true))
```

Tuist 的上傳會解析映射後的路徑，但 Xcode 的涵蓋率報告和 `xccov` 可能會排除這些檔案。請參閱 <.localized_link href="/guides/features/cache/xcode-cache#coverage-with-prefix-mapping">含路徑前綴映射的涵蓋率</.localized_link>。

### 略過的測試 {#skipped-tests}

當先前的成功執行已使用相同的雜湊值測試過某個測試 target 時，選擇性測試會略過該 target。該雜湊值涵蓋了 target 的原始碼、其測試以及所有依賴項，因此相同的雜湊值意味著對相同的程式碼執行相同的測試。Tuist 會重複使用先前執行為該 target 記錄的 [target 層級涵蓋率](#target-level-coverage)。如果當時沒有記錄任何數據（例如因為當時關閉了涵蓋率，或該執行超過 90 天），則無法承接數據，該 commit 的狀態將為 **不完整**。

選擇性執行也不會建置每個檔案。對於未編譯的檔案，只要這些檔案自上次完整執行以來未曾變更，Tuist 就會採用最近一次完整執行中的行數數據。這就是為什麼你預設分支上的 [完整執行](#full-runs) 至關重要。

你自己使用 `--skip-test-targets` 或 `-skip-testing` 略過的測試不會被承接：如果某次執行的 commit 略過了這些測試，且該 commit 的其他執行也沒有運行它們，則該 commit 的狀態為 **不完整**。被隔離略過的測試完全不計入涵蓋率：Tuist 既不會承接它們，也不會因此將 commit 標記為 **不完整**。

### 完整與不完整的 commit {#commit-status}

儀表板上的每個 commit 都有一個狀態：

| 狀態 | 含義 |
| --- | --- |
| 進行中 | 已有執行回報涵蓋率，但尚未針對該 commit 執行 `tuist coverage complete`。 |
| 完整 | 該 commit 方案中的所有測試均已執行或被承接。 |
| 不完整 | 部分涵蓋率無法確定，因此該數值僅為下限。 |
| 未測量 | 沒有執行回報該 commit 的涵蓋率。 |

分支的趨勢僅包含完整的 commit。當出現以下情況時，commit 會被視為不完整：

- 選擇性測試略過了一個無法承接的 target：先前的執行未記錄其涵蓋率、選擇性執行未建置的檔案自上次完整執行以來已發生變更，或者該 commit 變更了影響所有 target 的檔案，例如 `Package.resolved`、`Project.swift` 或 `.xcconfig`。
- 某次執行使用 `--skip-test-targets` 或 `-skip-testing` 略過了測試，且該 commit 的其他執行也沒有運行它們。
- 某次執行從二進制快取中以普通二進制檔的形式獲取了你的 target。
- 方案的每次執行都使用 `-only-testing` 進行了縮減。
- 方案的涵蓋率僅來自於含有未提交變更的 checkout 上的 CI 執行。

## 效能影響 {#performance-impact}

收集涵蓋率會增加額外開銷，主要發生在測試結束後，當 Xcode 寫入涵蓋率報告且 Tuist 匯出涵蓋率時。建置和運行測試所需的時間與未啟用涵蓋率時大致相同。插樁建置也會佔用更多磁碟空間，包括 DerivedData 和 Debug 二進制快取。Release 建置和歸檔不受影響。

## 限制 {#limitations}

### 收集涵蓋率的方案的 Release 建置 {#release-builds}

當方案的測試動作收集涵蓋率時，Xcode 也會對 `xcodebuild build` 為該方案從原始碼編譯的 target 進行插樁，適用於任何組態，包括 Release。`xcodebuild archive` 會忽略此設定，因此歸檔永遠不會被插樁。請分發歸檔，或使用帶有 `.options(coverage: false)` 的方案來建置 Release 產品。

### 其他涵蓋率工具 {#other-coverage-tools}

`-enableCodeCoverage YES` 僅決定執行是否收集涵蓋率，如同在 Xcode 中一樣。它不會讓 Tuist 從快取中讀取插樁二進制檔，因此請改用 `Tuist.swift` 選項或 `TUIST_COVERAGE_ENABLED`。

若要提供數據給其他涵蓋率工具，請讓 `tuist test` 將每次執行的涵蓋率寫入為 LCOV 格式。這與 Tuist 上傳的涵蓋率相同，包含相對於儲存庫的路徑以及來自二進制快取的程式碼：

```sh
tuist test --coverage-output-path coverage
```

每次執行會寫入 `coverage/<result bundle name>.lcov`。使用 `lcov -a` 合併分片執行的檔案。此選項需要開啟涵蓋率上傳。

Xcode 自身的涵蓋率報告及其讀取工具，僅包含該次執行中由 Xcode 建置的 target，絕不包含來自二進制快取的程式碼。Tuist 的上傳則會測量兩者。如果你希望在 Xcode 的報告中看到某個 target 的涵蓋率，請在生成專案時讓該 target 從原始碼建置：`tuist generate MyTarget` 會將 `MyTarget` 保留為原始碼，並從快取中獲取其餘部分。

## 查詢涵蓋率 {#querying}

`tuist coverage` 指令會讀取儀表板顯示的內容。若未指定 `--commit`，它們會讀取 `--branch` 或你預設分支的最新完整 commit：

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
```

所有指令均接受 `--json` 以便進行腳本處理。代理程式亦可透過 <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol 伺服器</.localized_link> 獲取相同數據。
