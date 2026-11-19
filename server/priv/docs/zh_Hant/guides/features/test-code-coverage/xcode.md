---
{
  "title": "Xcode 程式碼涵蓋率",
  "titleTemplate": ":title · 程式碼涵蓋率 · 功能 · 指南 · Tuist",
  "description": "將 Xcode 專案的程式碼涵蓋率上傳至 Tuist，並按檔案與提交追蹤。"
}
---
# Xcode 程式碼涵蓋率 {#xcode-code-coverage}

程式碼涵蓋率會告訴你測試執行了程式碼中的哪些行。Tuist 會上傳每次測試執行的行涵蓋率，並將一個提交中的所有執行合併為單一數值，分別針對專案、每個目標與每個檔案呈現。儀表板的 **程式碼涵蓋率** 頁面會依提交顯示，並呈現各分支的趨勢。

<!-- @snippet: ./_xcode-requirements -->

> [!TIP]
> 若你使用 Tuist 產生專案，請改參考<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">產生的專案指南</.localized_link>：它會測量來自二進位快取的程式碼，並延續選擇性測試所略過的測試目標之涵蓋率。

## 設定 {#setup}

### 收集涵蓋率 {#collect-coverage}

在你的 `Tuist.swift` 中開啟涵蓋率上傳。預設為關閉：

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "my-account/my-project",
    testInsights: .testInsights(coverage: .coverage(upload: true)),
    project: .xcode()
)
```

`TUIST_COVERAGE_UPLOAD` 環境變數（`1` 或 `0`）會優先於該選項，例如用於在執行來自分叉的拉取請求的工作中關閉上傳。

接著在你的 scheme 的測試動作中開啟 **程式碼涵蓋率**（**Edit Scheme › Test › Options**），或在執行時傳入 `-enableCodeCoverage YES`，並透過 `tuist xcodebuild test` 執行你的測試：

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -enableCodeCoverage YES
```

Tuist 會上傳該次執行收集的涵蓋率及其測試結果。

### 在 CI 上完成每個提交 {#complete-each-commit}

一個提交的涵蓋率通常來自多個工作：每個 scheme、每個分片或每個平台各一。Tuist 無法判斷最後一個工作何時回報，因此需要你告知。當某個提交的所有測試工作都完成後，在依賴所有這些工作的另一個工作中執行以下指令：

```sh
tuist coverage complete
```

該指令會從檢出的 `HEAD` 讀取提交，也就是你的測試所執行的提交；若要指定其他提交，請傳入 `--commit <sha>`。在提交完成之前，其涵蓋率會顯示為 **進行中**，且不會納入該分支的趨勢。<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#commit-status">產生的專案指南</.localized_link> 說明了各狀態。

## 略過的測試 {#skipped-tests}

當一次執行使用 `-skip-testing` 略過測試時，其測量的範圍會小於該提交測試所涵蓋的範圍，而 Tuist 也無法從先前的執行中延續這些測試。除非該提交另有其他執行涵蓋了這些測試，否則該提交的涵蓋率會標示為 **不完整**。若要讓提交保持完整，請在每個提交至少一次執行中執行所有測試。

被隔離略過的測試完全不屬於涵蓋率的一部分，因此它們永遠不會讓提交變成 **不完整**。

## 效能影響 {#performance-impact}

收集涵蓋率會增加額外負擔，主要發生在測試結束後，此時 Xcode 會寫入涵蓋率報告，而 Tuist 會匯出涵蓋率。建置與執行測試所需的時間與未啟用涵蓋率時大致相同。

## 查詢涵蓋率 {#querying}

`tuist coverage` 指令會讀取儀表板所顯示的內容。若未提供 `--commit`，它們會讀取 `--branch` 的最新已完成提交，或是你的預設分支：

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
tuist coverage targets                       # targets, least covered first, then those taken from the binary cache without coverage
tuist coverage commits --branch main         # a branch's commits with their status and change, newest first
tuist coverage runs --commit <sha>           # the test runs behind a commit, marked full, partial or discarded
tuist coverage branches                      # the branches with coverage
```

測試執行本身的涵蓋率可在 `tuist test show <test-run-id>` 中查看。

所有指令皆支援 `--json` 以便用於腳本化。
