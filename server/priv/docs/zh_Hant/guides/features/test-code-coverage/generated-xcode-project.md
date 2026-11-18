---
{
  "title": "生成的 Xcode 專案",
  "titleTemplate": ":title · 程式碼涵蓋率 · 功能 · 指南 · Tuist",
  "description": "測量 Tuist 生成的 Xcode 專案中每個檔案與每次提交的程式碼涵蓋率，包含被二進位快取與選擇性測試跳過的程式碼。"
}
---
# 產生的 Xcode 專案 {#generated-xcode-project-code-coverage}

程式碼涵蓋率會告訴你測試執行了哪些程式碼行。Tuist 會上傳每次 `tuist test` 執行的行涵蓋率，並將同一個提交的所有執行合併為單一數值，適用於整個專案、每個目標與每個檔案。儀表板的 **程式碼涵蓋率** 頁面會以每次提交顯示，並呈現各分支的趨勢。

<!-- @snippet: ./_xcode-requirements -->

當 Tuist 略過部分工作時，數值仍保持準確。來自 <.localized_link href="/guides/features/cache/module-cache">二進位快取</.localized_link> 的目標在建置時會加入涵蓋率計數器，因此其程式碼的測量方式與從原始碼建置的程式碼相同。而當 <.localized_link href="/guides/features/selective-testing/generated-xcode-project">選擇性測試</.localized_link> 略過某個測試目標時，該目標會保留先前執行時的涵蓋率，因為 Tuist 會在每次執行中記錄 [目標層級涵蓋率](#target-level-coverage)。

## 設定 {#setup}

### 開啟涵蓋率 {#turn-coverage-on}

在 `Tuist.swift` 的產生選項中開啟涵蓋率，並啟用涵蓋率上傳（預設為關閉）：

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

- Tuist 產生的每個配置方案的測試動作都會收集涵蓋率；你自行定義且未設定 `coverage` 的配置方案，其測試動作也會收集涵蓋率。若配置方案使用 `.options(coverage: false)` 或 `.options(coverage: true)`，則會保留其設定值。測試計畫會自行決定涵蓋率：針對 Tuist 產生的測試計畫，請將 `coverage: true` 傳入 `.testPlans(_:coverage:)`。
- 專案自身的目標會在 Debug 組態中以涵蓋率計數器讀取並預熱至二進位快取。請參閱 [運作方式](#instrumented-binaries)。

環境變數 `TUIST_COVERAGE_ENABLED` 與 `TUIST_COVERAGE_UPLOAD`（值為 `1` 或 `0`）的優先順序高於 `enabled` 與 `upload`。請在整個環境（例如 CI 工作流程）中設定，而非僅針對單一指令，以確保預熱快取與讀取快取的指令保持一致。

> [!IMPORTANT] KEEP THE VALUE THE SAME EVERYWHERE
> 產生選項會改變專案目標的快取鍵值，以及其測試目標的選擇性測試雜湊。在所有共用快取的機器上使用相同的值，不要從環境衍生該值（例如從 `Environment.isCI`）。關閉涵蓋率的執行不會重複使用開啟涵蓋率執行所產生的二進位檔或選擇性測試結果。

### 排除配置方案 {#leave-schemes-out}

某些測試套件不適合納入涵蓋率。例如，從另一個程序驅動你的 App 或 CLI 的驗收測試或端到端測試，會執行涵蓋率工具無法觀測的程式碼，收集涵蓋率只會讓它們變慢。請在該配置方案的測試動作中關閉涵蓋率：

```swift
.scheme(
    name: "AcceptanceTests",
    testAction: .targets(
        ["AcceptanceTests"],
        options: .options(coverage: false)
    )
)
```

不論 `Tuist.swift` 選項或 `TUIST_COVERAGE_ENABLED` 如何設定，該配置方案都會維持關閉涵蓋率，其執行也不會計入提交的涵蓋率。涵蓋率是以配置方案為單位收集，若要排除某個測試目標，請將其移至專屬的配置方案。

### 執行測試 {#run-your-tests}

照常使用 `tuist test` 執行測試：

```sh
tuist test
```

Tuist 會上傳該次執行收集的涵蓋率及其測試結果。這包含 <.localized_link href="/guides/features/test-sharding/generated-xcode-project">分片執行</.localized_link>，以及使用 `--without-building` 在其他工作中建置產品並進行測試的執行。若要让某次執行的涵蓋率不上傳至 Tuist（例如在執行來自分支的拉取請求的工作中），請設定 `TUIST_COVERAGE_UPLOAD=0`。

### 在 CI 上完成每次提交 {#complete-each-commit}

一次提交的涵蓋率通常來自多個工作：每個配置方案、每個分片或每個平台各一個。Tuist 無法判斷最後一個工作何時回報，因此需要你告知。當某次提交的所有測試工作都完成後，在依賴這些工作的另一個工作中執行以下指令：

```sh
tuist coverage complete
```

該指令會從檢出目錄或你的 CI 提供者讀取提交資訊；若要指定其他提交，請傳入 `--commit <sha>`。在提交標記為完成之前，其涵蓋率會顯示為 **進行中**，且不會納入該分支的趨勢。

### 在預設分支上執行完整測試套件 {#full-runs}

> [!IMPORTANT] SET UP A FULL RUN
> 只有在有先前的執行可承接被略過的目標時，選擇性測試才能讓提交的涵蓋率保持完整。請在預設分支上排程執行所有測試，且不啟用選擇性測試：
>
> ```sh
> tuist test --no-selective-testing
> ```
>
> 理想情況是每次合併時執行一次。對於變更較少的儲存庫，每天或每週執行一次可能已足夠。記錄的涵蓋率會在 31 天後過期，因此執行頻率應高於此間隔。

承接的涵蓋率依賴完整執行。完整執行會在涵蓋率過期前刷新每個目標的記錄涵蓋率，並讓 Tuist 取得選擇性執行未建置之檔案的最新狀態。儲存庫在兩次完整執行之間的變更越多，選擇性執行就越常發現自上次以來已變更的檔案，導致該提交的涵蓋率顯示為 **不完整**。

## 目標層級涵蓋率 {#target-level-coverage}

單次執行的涵蓋率反映的是整體執行所執行的內容，而非每個測試目標各自執行的內容。當選擇性測試略過某個目標時，Tuist 需要知道該目標在先前的執行中執行了哪些內容，才能承接其涵蓋率。

因此，Tuist 會在每次執行中記錄每個測試目標執行了哪些檔案與行號。這些資料來自 Xcode 為每個測試程序寫入的涵蓋率報告，無需額外連結或設定。此記錄僅在 macOS 與 iOS 模擬器上可用，不在實體裝置上。UI 測試不會記錄其所驅動 App 的任何資訊，因為 App 的程式碼在獨立的程序中執行。

## 運作方式 {#how-it-works}

### 插樁二進位檔 {#instrumented-binaries}

來自二進位快取的目標是預先建置的二進位檔，只有在該二進位檔建置時加入了涵蓋率計數器，測試執行才能測量其程式碼。開啟涵蓋率時，二進位快取會保留專案自身目標的插樁版本，且所有指令都會讀取並預熱該版本：

- **Debug 組態** 使用插樁版本：`tuist cache` 會預熱它，而 `tuist generate` 與 `tuist test` 會讀取它。
- **Release 組態** 一律使用未插樁版本，因此你交付的產品不會包含涵蓋率計數器。
- **外部套件** 一律使用未插樁版本。Tuist 僅測量你儲存庫中的程式碼。

請在與測試工作相同的環境中開啟涵蓋率並預熱快取，這樣 `tuist test` 才能找到插樁二進位檔。若某次執行收集了涵蓋率，但從快取取得的目標是未插樁二進位檔，Tuist 會發出警告，且不會測量其程式碼。<.localized_link href="/guides/features/cache/module-cache#code-coverage">模組快取</.localized_link> 詳細說明了這些版本。

### 跨機器的路徑 {#paths-across-machines}

插樁二進位檔會記錄相對於其建置時所在檢出目錄的原始碼路徑，因此在 CI 上預熱的二進位檔能在任何開發者的機器上正確測量對應的檔案。

<.localized_link href="/guides/features/cache/xcode-cache">Xcode 快取</.localized_link> 透過路徑前綴對應以相同方式運作。Tuist 在收集涵蓋率的建置中預設會關閉此功能，因為 Xcode 自身的涵蓋率報告無法解析對應後的路徑。在 Xcode 27 及更新版本中，開啟 `enableCaching` 並設定 `prefixMapping: true` 可維持啟用狀態，讓涵蓋率建置也能在不同檢出目錄間共享編譯結果：

```swift
.options(coverage: .coverage(enabled: true, prefixMapping: true))
```

Tuist 的上傳會解析對應後的路徑，但 Xcode 的涵蓋率報告與 `xccov` 可能會排除這些檔案。請參閱 <.localized_link href="/guides/features/cache/xcode-cache#coverage-with-prefix-mapping">含路徑前綴對應的涵蓋率</.localized_link>。

### 略過的測試 {#skipped-tests}

當先前的成功執行已使用相同的雜湊值測試過某個測試目標時，選擇性測試會略過該目標。雜湊值涵蓋目標的原始碼、其測試及其所有相依項目，因此相同的雜湊值代表對相同的程式碼執行相同的測試。Tuist 會重複使用先前執行為該目標記錄的 [目標層級涵蓋率](#target-level-coverage)。若當時未記錄任何資料（例如因為當時涵蓋率已關閉，或該執行超過 31 天），則無資料可承接，該提交會被標記為 **不完整**。

選擇性執行也不會建置每個檔案。對於未編譯的檔案，只要自上次完整執行以來檔案未變更，Tuist 就會採用最近一次完整執行中的行號資料。這就是為什麼你預設分支上的 [完整執行](#full-runs) 至關重要。

你自行使用 `--skip-test-targets` 或 `-skip-testing` 略過的測試不會被承接：若某提交的執行略過了這些測試，且該提交的其他執行也未執行它們，則該提交會被標記為 **不完整**。被隔離略過的測試完全不納入涵蓋率計算：Tuist 既不會承接它們，也不會因此將提交標記為 **不完整**。

### 完整與不完整的提交 {#commit-status}

儀表板上的每個提交都有一個狀態：

| 狀態 | 意義 |
| --- | --- |
| 進行中 | 已有執行回報涵蓋率，但尚未針對該提交執行 `tuist coverage complete`。 |
| 完整 | 該提交方案中的所有測試均已執行或被承接。 |
| 不完整 | 部分涵蓋率無法確定，因此該數值為下限。 |
| 未測量 | 沒有執行針對該提交回報涵蓋率。 |

分支的趨勢僅包含完整的提交。提交在不完整時的情況例如：

- 選擇性測試略過了一個無法承接的目標：先前的執行未記錄其涵蓋率、選擇性執行未建置的檔案自上次完整執行以來已變更，或該提交變更了影響所有目標的檔案，例如 `Package.resolved`、`Project.swift` 或 `.xcconfig`。
- 某次執行使用 `--skip-test-targets` 或 `-skip-testing` 略過了測試，且該提交的其他執行也未執行它們。
- 某次執行從二進位快取中以未插樁二進位檔的形式取得了你的目標。
- 方案的每次執行都使用 `-only-testing` 進行了縮減。
- 方案的涵蓋率僅來自於含有未提交變更之檢出目錄的 CI 執行。

## 效能影響 {#performance-impact}

收集涵蓋率會增加額外負擔，主要發生在測試結束後，Xcode 寫入涵蓋率報告且 Tuist 匯出涵蓋率期間。建置與執行測試所需的時間與未開啟涵蓋率時大致相同。插樁建置也會佔用更多磁碟空間，包括 DerivedData 與 Debug 二進位快取。Release 建置與封存檔不受影響。

## 限制 {#limitations}

### 收集涵蓋率之方案的 Release 建置 {#release-builds}

當方案的測試動作收集涵蓋率時，Xcode 也會對 `xcodebuild build` 為該方案從原始碼編譯的目標進行插樁，無論任何組態（包含 Release）。`xcodebuild archive` 會忽略此設定，因此封存檔永遠不會被插樁。請分發封存檔，或使用具備 `.options(coverage: false)` 的方案來建置 Release 產品。

### 其他涵蓋率工具 {#other-coverage-tools}

`-enableCodeCoverage YES` 僅決定執行是否收集涵蓋率，如同在 Xcode 中一樣。它不會讓 Tuist 從快取讀取插樁二進位檔，因此請改用 `Tuist.swift` 選項或 `TUIST_COVERAGE_ENABLED`。

若要提供資料給其他涵蓋率工具，請讓 `tuist test` 將每次執行的涵蓋率寫入為 LCOV 格式。這與 Tuist 上傳的涵蓋率相同，包含相對於儲存庫的路徑以及來自二進位快取的程式碼：

```sh
tuist test --coverage-output-path coverage
```

每次執行會寫入 `coverage/<result bundle name>.lcov`。請使用 `lcov -a` 合併分片執行的檔案。此選項需要開啟涵蓋率上傳。

Xcode 自身的涵蓋率報告及其讀取工具，僅包含該次執行中由 Xcode 建置的目標，絕不包含來自二進位快取的程式碼。Tuist 的上傳則會測量兩者。若你希望在 Xcode 的報告中看到某個目標的涵蓋率，請產生該目標從原始碼建置的專案：`tuist generate MyTarget` 會將 `MyTarget` 保留為原始碼建置，其餘則從快取取得。

## 查詢涵蓋率 {#querying}

`tuist coverage` 指令會讀取儀表板顯示的內容。若未指定 `--commit`，它們會讀取 `--branch` 或你預設分支的最新完整提交：

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
tuist coverage targets                       # targets, least covered first, then those taken from the binary cache without coverage
tuist coverage commits --branch main         # a branch's commits with their status and change, newest first
tuist coverage runs --commit <sha>           # the test runs behind a commit, marked full, partial or discarded
tuist coverage branches                      # the branches with coverage
```

測試執行自身的涵蓋率顯示於 `tuist test show <test-run-id>`。

所有指令皆接受 `--json` 以便進行腳本處理。代理程式也可透過 <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol 伺服器</.localized_link> 存取相同的資料。
