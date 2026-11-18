---
{
  "title": "Xcode 程式碼涵蓋率",
  "titleTemplate": ":title · 程式碼涵蓋率 · 功能 · 指南 · Tuist",
  "description": "將 Xcode 專案的程式碼涵蓋率上傳至 Tuist，並按檔案與提交追蹤。"
}
---
# Xcode 程式碼涵蓋率 {#xcode-code-coverage}

程式碼涵蓋率會告訴你測試執行了哪些程式碼行。Tuist 會上傳每次測試執行的行涵蓋率，並將同一個提交的多次執行合併為單一數值，適用於專案、每個目標以及每個檔案。儀表板的 **程式碼涵蓋率** 頁面會顯示每個提交的涵蓋率，以及每個分支的趨勢。

<!-- @snippet: ./_xcode-requirements -->

> [!TIP]
> 如果你使用 Tuist 產生專案，請改參考<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">產生的專案指南</.localized_link>：它會測量來自二進位快取的程式碼，並延續選擇性測試所跳過的測試目標之涵蓋率。

## 設定 {#setup}

### 收集涵蓋率 {#collect-coverage}

在你的 `Tuist.swift` 中開啟涵蓋率上傳功能。預設為關閉：

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "my-account/my-project",
    testInsights: .testInsights(coverage: .coverage(upload: true)),
    project: .xcode()
)
```

`TUIST_COVERAGE_UPLOAD` 環境變數（`1` 或 `0`）的優先順序高於該選項，例如可用於在執行來自分叉倉庫的拉取請求的工作時關閉上傳。

接著在你的 scheme 測試動作中開啟 **程式碼涵蓋率**（**Edit Scheme › Test › Options**），或在執行時傳遞 `-enableCodeCoverage YES`，並透過 `tuist xcodebuild test` 執行你的測試：

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -enableCodeCoverage YES
```

Tuist 會將執行期間收集的涵蓋率連同測試結果一起上傳。

### 在 CI 上完成每個提交 {#complete-each-commit}

一個提交的涵蓋率通常來自多個工作：每個 scheme、每個分片或每個平台各一個。Tuist 無法判斷最後一個工作何時回報，因此需要你明確告知。當某個提交的所有測試工作都完成後，在依賴這些工作的另一個工作中執行以下指令：

```sh
tuist coverage complete
```

在提交完成之前，其涵蓋率會顯示為 **進行中**，且不會納入該分支的趨勢計算。<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#commit-status">產生的專案指南</.localized_link> 說明了每種狀態。

## 已略過的測試 {#skipped-tests}

當一次執行使用 `-skip-testing` 略過測試時，它所測量的範圍會小於該提交所有測試的涵蓋範圍，而 Tuist 也無法從先前的執行中延續這些測試的涵蓋率。該提交的涵蓋率會標示為 **不完整**，除非該提交另有其他執行包含了這些測試。若要讓提交保持完整，請確保每個提交至少有一次執行涵蓋所有測試。

被隔離機制略過的測試完全不計入涵蓋率，因此它們永遠不會導致提交變成 **不完整**。

## 效能影響 {#performance-impact}

收集涵蓋率會增加額外負擔，主要發生在測試結束後，此時 Xcode 會寫入涵蓋率報告，而 Tuist 則匯出涵蓋率資料。建置與執行測試所需的時間與未啟用涵蓋率時大致相同。

## 查詢涵蓋率 {#querying}

`tuist coverage` 指令會讀取儀表板所顯示的資料。若未提供 `--commit`，則會讀取 `--branch` 的最新已完成提交，或是你的預設分支的最新已完成提交：

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
```

所有指令都支援 `--json` 以便用於腳本化。
