---
{
  "title": "Xcode 代碼覆蓋率",
  "titleTemplate": ":title · 代碼覆蓋率 · 功能 · 指南 · Tuist",
  "description": "將 Xcode 專案的代碼覆蓋率上載到 Tuist，並按檔案及提交追蹤。"
}
---
# Xcode 程式碼覆蓋率 {#xcode-code-coverage}

程式碼覆蓋率會告訴你測試執行了程式碼中的哪些行。Tuist 會上傳每次測試執行的行覆蓋率，並將同一個 commit 的多次執行合併為單一數值，涵蓋整個專案、每個 target 及每個檔案。儀表板的 **程式碼覆蓋率** 頁面會按 commit 顯示，並呈現每個分支的趨勢。

<!-- @snippet: ./_xcode-requirements -->

> [!TIP]
> 如果你使用 Tuist 產生專案，請改為參閱<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">已產生專案指南</.localized_link>：它會測量來自二進制快取的程式碼，並延續選擇性測試所略過的測試 target 之覆蓋率。

## 設定 {#setup}

### 收集覆蓋率 {#collect-coverage}

在你的 `Tuist.swift` 中開啟覆蓋率上傳功能。預設為關閉：

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "my-account/my-project",
    testInsights: .testInsights(coverage: .coverage(upload: true)),
    project: .xcode()
)
```

`TUIST_COVERAGE_UPLOAD` 環境變數（`1` 或 `0`）的優先級高於該選項，例如可用於在執行來自 fork 的 pull request 的工作時關閉上傳。

接著在你的 scheme 的測試動作中開啟 **程式碼覆蓋率**（**Edit Scheme › Test › Options**），或在執行時傳遞 `-enableCodeCoverage YES`，並透過 `tuist xcodebuild test` 執行你的測試：

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -enableCodeCoverage YES
```

Tuist 會上傳該次執行所收集的覆蓋率及其測試結果。

### 在 CI 上完成每個 commit {#complete-each-commit}

一個 commit 的覆蓋率通常來自多個工作：每個 scheme、每個分片或每個平台各一個。Tuist 無法判斷最後一個工作何時回報，因此需要你告知。當某個 commit 的所有測試工作都完成後，在依賴所有這些工作的另一個工作中執行以下指令：

```sh
tuist coverage complete
```

在 commit 完成之前，其覆蓋率會顯示為 **進行中**，且不會納入該分支的趨勢計算。<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#commit-status">已產生專案指南</.localized_link> 說明了每種狀態。

## 略過的測試 {#skipped-tests}

當某次執行使用 `-skip-testing` 略過測試時，它所測量的範圍會少於該 commit 的測試所涵蓋的範圍，而 Tuist 無法從較早的執行中延續這些測試。除非該 commit 另有其他執行跑了這些測試，否則該 commit 的覆蓋率會標示為 **不完整**。若要讓 commit 保持完整，請確保每個 commit 至少有一次執行跑遍所有測試。

被隔離略過的測試完全不計入覆蓋率，因此它們永遠不會讓 commit 變成 **不完整**。

## 效能影響 {#performance-impact}

收集覆蓋率會增加額外負擔，主要發生在測試結束後，此時 Xcode 會寫入其覆蓋率報告，而 Tuist 則匯出覆蓋率資料。建置與執行測試所需的時間與未開啟覆蓋率時大致相同。

## 查詢覆蓋率 {#querying}

`tuist coverage` 指令會讀取儀表板所顯示的資料。若未提供 `--commit`，它們會讀取 `--branch` 的最新已完成 commit，或是你的預設分支的最新已完成 commit：

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
tuist coverage targets                       # targets, least covered first, then those taken from the binary cache without coverage
tuist coverage commits --branch main         # a branch's commits with their status and change, newest first
tuist coverage runs --commit <sha>           # the test runs behind a commit, marked full, partial or discarded
tuist coverage branches                      # the branches with coverage
```

個別測試執行的覆蓋率可在 `tuist test show <test-run-id>` 中查看。

所有指令都支援 `--json` 以便進行腳本處理。
